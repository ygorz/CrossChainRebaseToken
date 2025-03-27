// SPDX-License-Identifier: MIT

pragma solidity ^0.8.24;

import {IRebaseToken} from "./interfaces/IRebaseToken.sol";

contract Vault {
    // we need to pass the token address to the constructor
    // create a deposit function that mints tokens to the user equal to the amount of ETH the user sent
    // create a redeem function that burns tokens from the user and sends the user ETH
    // create a way to add rewards to the vault

    /*==================== ERRORS =============================*/
    error Vault__RedeemFailed();

    /*==================== EVENTS =============================*/
    event Deposit(address indexed user, uint256 amount);
    event Redeem(address indexed user, uint256 amount);

    /*==================== STATE VARIABLES ====================*/
    IRebaseToken private immutable i_rebaseToken;

    /*==================== FUNCTIONS ==========================*/
    constructor(IRebaseToken _rebaseToken) {
        i_rebaseToken = _rebaseToken;
    }

    receive() external payable {}

    /**
     * @notice Allows users to deposit ETH into the vault and mint rebase tokens in return
     */
    function deposit() external payable {
        // we need to use the amount of ETH the user has sent to mint tokens to the user
        // emit an event
        i_rebaseToken.mint(msg.sender, msg.value);
        emit Deposit(msg.sender, msg.value);
    }

    /**
     * @notice Allows users to redeem their rebase tokens for ETH
     * @param _amount The amount of tokens to redeem
     */
    function redeem(uint256 _amount) external {
        if (_amount == type(uint256).max) {
            _amount = i_rebaseToken.balanceOf(msg.sender);
        }
        // 1. burn the tokens from the user
        i_rebaseToken.burn(msg.sender, _amount);
        // 2. send the user ETH
        (bool success,) = payable(msg.sender).call{value: _amount}("");
        if (!success) {
            revert Vault__RedeemFailed();
        }
        emit Redeem(msg.sender, _amount);
    }

    /**
     * @notice Get the address of the Rebase Token.
     * @return The address of the Rebase Token.
     */
    function getRebaseTokenAddress() external view returns (address) {
        return address(i_rebaseToken);
    }
}
