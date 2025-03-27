// SPDX-License-Identifier: MIT

pragma solidity ^0.8.24;

import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {AccessControl} from "@openzeppelin/contracts/access/AccessControl.sol";

/**
 * @title RebaseToken
 * @author George Gorzhiyev
 * @notice This is to follow along with the "Cross Chain Rebase Token" lesson on Cyfrin Updraft.
 * @notice This is a cross-chain rebase token that incentivizes users to deposit into a vault and gain interest in rewards.
 * @notice The interest rate in the smart contract can only decrease.
 * @notice Each user will have their own interest rate that is the global interest rate at the time of deposit.
 */

// 5 * 1e27 =
contract RebaseToken is ERC20, Ownable, AccessControl {
    /*==================== ERRORS =============================*/
    error RebaseToken__InterestRateCanOnlyDecrease(uint256 currentInterestRate, uint256 newInterestRate);

    /*==================== EVENTS =============================*/
    event InterestRateSet(uint256 indexed newInterestRate);

    /*==================== STATE VARIABLES ====================*/
    uint256 private constant PRECISION_FACTOR = 1e18;
    bytes32 private constant MINT_AND_BURN_ROLE = keccak256("MINT_AND_BURN_ROLE");
    uint256 private s_interestRate = (5 * PRECISION_FACTOR) / 1e8;

    mapping(address => uint256) private s_userInterestRate;
    mapping(address => uint256) private s_userLastUpdatedTimestamp;

    /*==================== FUNCTIONS ==========================*/
    constructor() ERC20("Rebase Token", "RBT") Ownable(msg.sender) {}

    function grantMintAndBurnRole(address _account) external onlyOwner {
        _grantRole(MINT_AND_BURN_ROLE, _account);
    }

    /**
     * @notice Set the interest rate for the contract.
     * @param _newInterestRate The new interest rate to set.
     * @dev The interest rate can only decrease.
     */
    function setInterestRate(uint256 _newInterestRate) external onlyOwner {
        if (_newInterestRate >= s_interestRate) {
            revert RebaseToken__InterestRateCanOnlyDecrease(s_interestRate, _newInterestRate);
        }

        s_interestRate = _newInterestRate;
        emit InterestRateSet(_newInterestRate);
    }

    /**
     * @notice Get the principle balance of a user. This is the number of tokens that have currently been minted to the user, not including any interest that has accrued since the last time the user interacted with the protocol.
     * @param _user The user to get the principle balance for.
     * @return The principle balance of the user.
     */
    function principleBalanceOf(address _user) external view returns (uint256) {
        return super.balanceOf(_user);
    }

    /**
     * @notice Mint the user tokens when they deposit into the vault.
     * @param _to The user to mint the tokens to.
     * @param _amount The amount of tokens to mint to the user.
     */
    function mint(address _to, uint256 _amount) external onlyRole(MINT_AND_BURN_ROLE) {
        _mintAccruedInterest(_to);
        s_userInterestRate[_to] = s_interestRate;
        _mint(_to, _amount);
    }

    /**
     * @notice Burn the user tokens when they withdraw from the vault.
     * @param _from The user to burn the tokens from.
     * @param _amount The amount of tokens to burn from the user.
     */
    function burn(address _from, uint256 _amount) external onlyRole(MINT_AND_BURN_ROLE) {
        _mintAccruedInterest(_from);
        _burn(_from, _amount);
    }

    /**
     * @notice Calculate the balance for the user including the interest that has accumulated since the last update.
     * (principle balance) + some interest that has accrued
     * @param _user The user to calculate the balance of.
     * @return The balance of the user including the interest that has accumulated since the last update.
     */
    function balanceOf(address _user) public view override returns (uint256) {
        // get the current principal balance of the user (number of tokens that have actually be minted to the user)
        // multiply the principle by the interest that has accumulated in the time since the balance has accumulated
        return (super.balanceOf(_user) * _calculateUserAccumulatedInterestSinceLastUpdate(_user)) / PRECISION_FACTOR;
    }

    /**
     * @notice Transfer tokens from one user to another.
     * @param _recipient The user to transfer the tokens to.
     * @param _amount The amount of tokens to transfer.
     * @return True if the transfer was successful.
     */
    function transfer(address _recipient, uint256 _amount) public override returns (bool) {
        _mintAccruedInterest(msg.sender);
        _mintAccruedInterest(_recipient);

        if (_amount == type(uint256).max) {
            _amount = balanceOf(msg.sender);
        }

        if (balanceOf(_recipient) == 0) {
            s_userInterestRate[_recipient] = s_userInterestRate[msg.sender];
        }

        return super.transfer(_recipient, _amount);
    }

    /**
     * @notice Transfer tokens from one user to another.
     * @param _sender The user to transfer the tokens from.
     * @param _recipient The user to transfer the tokens to.
     * @param _amount The amount of tokens to transfer.
     * @return True if the transfer was successful.
     */
    function transferFrom(address _sender, address _recipient, uint256 _amount) public override returns (bool) {
        _mintAccruedInterest(_sender);
        _mintAccruedInterest(_recipient);

        if (_amount == type(uint256).max) {
            _amount = balanceOf(_sender);
        }

        if (balanceOf(_recipient) == 0) {
            s_userInterestRate[_recipient] = s_userInterestRate[_sender];
        }

        return super.transferFrom(_sender, _recipient, _amount);
    }

    /**
     * @notice Calculate the interest that has accumulated since the last update.
     * @param _user The user to calculate the interest that has accumulated for.
     * @return linearInterest The interest that has accumulated since the last update.
     */
    function _calculateUserAccumulatedInterestSinceLastUpdate(address _user)
        internal
        view
        returns (uint256 linearInterest)
    {
        // we need to calculate the interest that has accumulated since the last update
        // this is going to be linear growth with time
        // 1. calculate the time since the last update
        // 2. calculate the amount of linear growth
        // principal amount (1+ (user interest rate * time elapsed))
        // If they deposit 10 tokens
        // Time elapsed is 2 seconds
        // Interest rate is 0.5% per second
        // 10 + (10 * 0.5 * 2) = 20
        uint256 timeElapsed = block.timestamp - s_userLastUpdatedTimestamp[_user];
        linearInterest = (PRECISION_FACTOR + (s_userInterestRate[_user] * timeElapsed));
    }

    /**
     * @notice Mint the accrued interest to the user since the last time they interacted with the protocol (e.g. burn, mint, transfer).
     * @param _user The user to mint the accrued interest to.
     */
    function _mintAccruedInterest(address _user) internal {
        // (1) find their current balance of Rebase tokens that have been minted by the user -> principal balance
        uint256 previousPrincipleBalance = super.balanceOf(_user);
        // (2) calculate their current balance including any interest -> balanceOf
        uint256 currentBalance = balanceOf(_user);
        // calculate the number of tokens that need to be minted to the user > (2) - (1)
        uint256 balanceIncrease = currentBalance - previousPrincipleBalance;
        // set the users last time stamp
        s_userLastUpdatedTimestamp[_user] = block.timestamp;
        // call _mint to mint tokens of the user
        _mint(_user, balanceIncrease);
    }

    /**
     * @notice Get the interest rate that is currently set for the contract. Any future deposited will receive this interest rate.
     * @return The current interest rate of the contract.
     */
    function getInterestRate() external view returns (uint256) {
        return s_interestRate;
    }

    /**
     * @notice Get the interest rate of the user.
     * @param _user The user to get the interest rate for.
     * @return The interest rate of the user.
     */
    function getUserInterestRate(address _user) external view returns (uint256) {
        return s_userInterestRate[_user];
    }
}
