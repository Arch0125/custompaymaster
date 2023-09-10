// SPDX-License-Identifier: GPL-3.0
pragma solidity ^0.8.12;

/* solhint-disable reason-string */

import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "../src/account-abstraction/contracts/core/BasePaymaster.sol";

/**
 * A sample paymaster that can pay gas in multiple ERC20 tokens.
 * The tokens which can be used by the paymaster are set by the owner.
    * The paymaster can be used by any account, but the owner can withdraw tokens from the paymaster's balance.
    * The exchange rate is fixed, since it can't reference an external Uniswap or other exchange contract.
    * getTokenValueOfEth provides token exchange rate, settable by the owner.
    * This paymaster takes array of token addresses as paymasterAndData.
    * Single or Multiple tokens can be used to pay for gas based on the balance of the account.
    
 */
contract CustomERC20Paymaster is BasePaymaster {
    using UserOperationLib for UserOperation;
    using SafeERC20 for IERC20;

    //calculated cost of the postOp
    uint256 public constant COST_OF_POST = 35000;

    mapping(address => bool) allowedTokens;
    mapping(address => uint256) public ethToTokenRate;

    constructor(IEntryPoint _entryPoint) BasePaymaster(_entryPoint) {}

    /**
     * owner of the paymaster should add supported tokens
     */
    function addToken(IERC20 token, uint256 exchangeRate) external onlyOwner {
        allowedTokens[address(token)] = true;
        ethToTokenRate[address(token)] = exchangeRate;
    }

    /**
     * translate the given eth value to token amount
    * @param account the account sending the user op
     * @param tokenAddresses the tokens to use
     * @param ethBought the required eth value we want to "buy"
     * @return requiredTokens the amount of tokens required to get this amount of eth
     */
    function getTokenValueOfEth(
        address account,
        address[] memory tokenAddresses,
        uint256 ethBought
    ) internal view virtual returns (uint256[] memory) {
        uint256[] memory rates = new uint256[](tokenAddresses.length);
        for (uint256 i = 0; i < tokenAddresses.length; i++) {
            if (
                IERC20(tokenAddresses[i]).balanceOf(account) >=
                ethBought * ethToTokenRate[tokenAddresses[i]]
            ) {
                rates[i] = ethBought * ethToTokenRate[tokenAddresses[i]];
                break;
            } else {
                rates[i] = IERC20(tokenAddresses[i]).balanceOf(account);
            }
        }
        return rates;
    }

    /**
     * Validate the request:
     * The sender should have enough token balance to pay for the gas.
     * The tokens to use are specified in the paymasterAndData.
     * Tokens should be whitelisted by the owner, otherwise revert.
        * @param userOp - the user operation to validate
        * @param userOpHash - the hash of the user operation
        * @param maxCost - the maximum cost of the operation
        * @return context - the context to pass to postOp
        * @return validationData - the validation data to pass to postOp
     */
    function _validatePaymasterUserOp(
        UserOperation calldata userOp,
        bytes32 userOpHash,
        uint256 maxCost
    )
        internal
        view
        override
        returns (bytes memory context, uint256 validationData)
    {
        (userOpHash);
        // verificationGasLimit is dual-purposed, as gas limit for postOp. make sure it is high enough
        require(
            userOp.verificationGasLimit > COST_OF_POST,
            "DepositPaymaster: gas too low for postOp"
        );

        bytes calldata paymasterAndData = userOp.paymasterAndData;
        require(
            paymasterAndData.length >= 20,
            "DepositPaymaster: paymasterAndData must specify tokens"
        );

        uint256 noOfTokens = paymasterAndData.length / 20;
        address[] memory tokenAddresses = new address[](noOfTokens - 1);

        for (uint i = 1; i < noOfTokens; i++) {
            tokenAddresses[i - 1] = address(
                bytes20(paymasterAndData[i * 20:(i + 1) * 20])
            );
        }

        for (uint i = 0; i < noOfTokens - 1; i++) {
            require(
                allowedTokens[tokenAddresses[i]],
                "DepositPaymaster: unsupported token"
            );
        }
        address account = userOp.getSender();
        uint256[] memory maxTokenCost = getTokenValueOfEth(
            account,
            tokenAddresses,
            maxCost
        );
        for (uint i = 0; i < noOfTokens - 1; i++) {
            IERC20 token = IERC20(tokenAddresses[i]);
            require(
                token.balanceOf(account) >= maxTokenCost[i],
                "DepositPaymaster: insufficient balance"
            );
        }
        uint256 gasPriceUserOp = userOp.gasPrice();
        return (
            abi.encode(
                account,
                tokenAddresses,
                gasPriceUserOp,
                maxTokenCost,
                maxCost
            ),
            0
        );
    }

    /**
     * perform the post-operation to charge the sender for the gas.
     */
    function _postOp(
        PostOpMode mode,
        bytes calldata context,
        uint256 actualGasCost
    ) internal override {
        (
            address account,
            address[] memory tokenAddresses,
            uint256 gasPricePostOp,
            uint256[] memory maxTokenCost,
            uint256 maxCost
        ) = abi.decode(
                context,
                (address, address[], uint256, uint256[], uint256)
            );
        //use same conversion rate as used for validation.
        for (uint i = 0; i < maxTokenCost.length; i++) {
            uint256 actualTokenCost = ((actualGasCost +
                COST_OF_POST *
                gasPricePostOp) * maxTokenCost[i]) / maxCost;
            IERC20 token = IERC20(tokenAddresses[i]);
            token.safeTransferFrom(account, address(this), actualTokenCost);
        }
    }
}
