// SPDX-License-Identifier: GPL-3.0
pragma solidity ^0.8.12;

/* solhint-disable reason-string */

import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "../src/account-abstraction/contracts/core/BasePaymaster.sol";

/**
 * A sample paymaster that defines itself as a token to pay for gas.
 * The paymaster IS the token to use, since a paymaster cannot use an external contract.
 * Also, the exchange rate has to be fixed, since it can't reference an external Uniswap or other exchange contract.
 * subclass should override "getTokenValueOfEth" to provide actual token exchange rate, settable by the owner.
 * Known Limitation: this paymaster is exploitable when put into a batch with multiple ops (of different accounts):
 * - while a single op can't exploit the paymaster (if postOp fails to withdraw the tokens, the user's op is reverted,
 *   and then we know we can withdraw the tokens), multiple ops with different senders (all using this paymaster)
 *   in a batch can withdraw funds from 2nd and further ops, forcing the paymaster itself to pay (from its deposit)
 * - Possible workarounds are either use a more complex paymaster scheme (e.g. the DepositPaymaster) or
 *   to whitelist the account and the called method ids.
 */
contract DynamicTokensPaymaster is BasePaymaster {
    //calculated cost of the postOp
    uint256 public constant COST_OF_POST = 15000;

    address public immutable theFactory;

    mapping(address => bool) allowedTokens;
    mapping(address => uint256) public ethToTokenRate;

    constructor(
        address accountFactory,
        IEntryPoint _entryPoint
    ) BasePaymaster(_entryPoint) {
        theFactory = accountFactory;
    }

    /**
     * transfer paymaster ownership.
     * owner of this paymaster is allowed to withdraw funds (tokens transferred to this paymaster's balance)
     * when changing owner, the old owner's withdrawal rights are revoked.
     */
    function transferOwnership(
        address newOwner
    ) public virtual override onlyOwner {
        super.transferOwnership(newOwner);
    }

    /**
     * owner of the paymaster should add supported tokens
     */
    function addToken(IERC20 token, uint256 exchangeRate) external onlyOwner {
        allowedTokens[address(token)] = true;
        ethToTokenRate[address(token)] = exchangeRate;
    }

    //Note: this method assumes a fixed ratio of token-to-eth. subclass should override to supply oracle
    // or a setter.
    function getTokenValueOfEth(
        address account,
        address[] memory tokenAddresses,
        uint256 requiredPreFund
    ) internal view virtual returns (uint256[] memory) {
        uint256[] memory rates = new uint256[](tokenAddresses.length);
        uint256 totalEth = requiredPreFund;
        for (uint256 i = 0; i < tokenAddresses.length; i++) {
            if (
                IERC20(tokenAddresses[i]).balanceOf(account) >=
                totalEth * ethToTokenRate[tokenAddresses[i]]
            ) {
                rates[i] = totalEth * ethToTokenRate[tokenAddresses[i]];
                totalEth = 0;
                break;
            } else {
                rates[i] = IERC20(tokenAddresses[i]).balanceOf(account);
                totalEth -= rates[i] / ethToTokenRate[tokenAddresses[i]];
            }
        }
        require(totalEth == 0, "DepositPaymaster: total gas not paid");
        return rates;
    }

    /**
     * validate the request:
     * if this is a constructor call, make sure it is a known account.
     * verify the sender has enough tokens.
     * (since the paymaster is also the token, there is no notion of "approval")
     */
    function _validatePaymasterUserOp(
        UserOperation calldata userOp,
        bytes32 userOpHash,
        uint256 requiredPreFund
    )
        internal
        view
        override
        returns (bytes memory context, uint256 validationData)
    {
        require(
            userOp.verificationGasLimit > COST_OF_POST,
            "TokenPaymaster: gas too low for postOp"
        );

        bytes calldata paymasterAndData = userOp.paymasterAndData;
        require(
            paymasterAndData.length >= 20,
            "DepositPaymaster: paymasterAndData must specify tokens"
        );

        uint256 noOfTokens = paymasterAndData.length / 20;
        address[] memory tokenAddresses = new address[](noOfTokens - 1);

        // for (uint i = 1; i < noOfTokens; ++i) {
        //     tokenAddresses[i - 1] = address(
        //         bytes20(paymasterAndData[i * 20:(i + 1) * 20])
        //     );
        // }

        tokenAddresses[0] = address(
            bytes20(paymasterAndData[20:40])
        );

        tokenAddresses[1] = address(
            bytes20(paymasterAndData[40:60])
        );

        for (uint i = 0; i < noOfTokens - 1; i++) {
            require(
                allowedTokens[tokenAddresses[i]],
                "DepositPaymaster: unsupported token"
            );
        }
        address account = userOp.sender;

        uint256[] memory tokenPreFund = getTokenValueOfEth(
            account,
            tokenAddresses,
            requiredPreFund
        );

        // verificationGasLimit is dual-purposed, as gas limit for postOp. make sure it is high enough
        // make sure that verificationGasLimit is high enough to handle postOp

        if (userOp.initCode.length != 0) {
            _validateConstructor(userOp);
            for (uint i = 0; i < noOfTokens - 1; i++) {
                IERC20 token = IERC20(tokenAddresses[i]);
                require(
                    token.balanceOf(account) >= tokenPreFund[i],
                    "Dynamic Paymaster: insufficient balance"
                );
            }
        } else {
            for (uint i = 0; i < noOfTokens - 1; i++) {
                IERC20 token = IERC20(tokenAddresses[i]);
                require(
                    token.balanceOf(account) >= tokenPreFund[i],
                    "Dynamic Paymaster: insufficient balance"
                );
            }
        }

        return (abi.encode(userOp.sender, tokenAddresses), 0);
    }

    // when constructing an account, validate constructor code and parameters
    // we trust our factory (and that it doesn't have any other public methods)
    function _validateConstructor(
        UserOperation calldata userOp
    ) internal view virtual {
        address factory = address(bytes20(userOp.initCode[0:20]));
        require(factory == theFactory, "TokenPaymaster: wrong account factory");
    }

    /**
     * actual charge of user.
     * this method will be called just after the user's TX with mode==OpSucceeded|OpReverted (account pays in both cases)
     * BUT: if the user changed its balance in a way that will cause  postOp to revert, then it gets called again, after reverting
     * the user's TX , back to the state it was before the transaction started (before the validatePaymasterUserOp),
     * and the transaction should succeed there.
     */
    function _postOp(
        PostOpMode mode,
        bytes calldata context,
        uint256 actualGasCost
    ) internal override {
        //we don't really care about the mode, we just pay the gas with the user's tokens.
        (mode);
        (address sender, address[] memory tokenAddresses) = abi.decode(context, (address, address[]));
        uint256[] memory tokenCharge = getTokenValueOfEth(
            sender,
            tokenAddresses,
            (actualGasCost + COST_OF_POST)
        );
        //actualGasCost is known to be no larger than the above requiredPreFund, so the transfer should succeed.
        for(uint i = 0; i < tokenAddresses.length; i++) {
            IERC20(tokenAddresses[i]).transferFrom(sender, address(this), tokenCharge[i]);
        }
    }
}
