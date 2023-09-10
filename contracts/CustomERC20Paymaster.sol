// SPDX-License-Identifier: GPL-3.0
pragma solidity ^0.8.12;

/* solhint-disable reason-string */

import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "../src/account-abstraction/contracts/core/BasePaymaster.sol";

/**
 * A sample paymaster that defines itself as a token to pay for gas.
 * The paymaster IS the token to use, since a paymaster cannot use an external contract.
 * Also, the exchange rate has to be fixed, since it can't reference an external Uniswap or other exchange contract.
 * subclass should override "getTokenValueOfEth" to provide actual token exchange rate, settable by the owner.
 * Known Limitation: this paymaster is exploitable when put into a batch with multiple ops (of different accounts):
 * - while a single op can't exploit the paymaster (if postOp fails to withdraw the t\okens, the user's op is reverted,
 *   and then we know we can withdraw the tokens), multiple ops with different senders (all using this paymaster)
 *   in a batch can withdraw funds from 2nd and further ops, forcing the paymaster itself to pay (from its deposit)
 * - Possible workarounds are either use a more complex paymaster scheme (e.g. the DepositPaymaster) or
 *   to whitelist the account and the called method ids.
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
     * @param tokenAddresses the token to use
     * @param ethBought the required eth value we want to "buy"
     * @return requiredTokens the amount of tokens required to get this amount of eth
     */
    function getTokenValueOfEth(
        address[] memory tokenAddresses,
        uint256 ethBought
    ) internal view virtual returns (uint256[] memory) {
        uint256[] memory rates = new uint256[](tokenAddresses.length);
        for (uint256 i = 0; i < tokenAddresses.length; i++) {
            rates[i] = ethToTokenRate[tokenAddresses[i]] * ethBought;
        }
        return rates;
    }

    /**
     * Validate the request:
     * The sender should have enough deposit to pay the max possible cost.
     * Note that the sender's balance is not checked. If it fails to pay from its balance,
     * this deposit will be used to compensate the paymaster for the transaction.
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
        address[] memory tokenAddresses = new address[](noOfTokens);

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
     * in normal mode, use transferFrom to withdraw enough tokens from the sender's balance.
     * in case the transferFrom fails, the _postOp reverts and the entryPoint will call it again,
     * this time in *postOpReverted* mode.
     * In this mode, we use the deposit to pay (which we validated to be large enough)
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
        for (uint i = 0; i < tokenAddresses.length - 1; i++) {
            uint256 actualTokenCost = ((actualGasCost +
                COST_OF_POST *
                gasPricePostOp) * maxTokenCost[i]) / maxCost;
            IERC20 token = IERC20(tokenAddresses[i]);
            token.safeTransferFrom(account, address(this), actualTokenCost);
        }
    }
}
