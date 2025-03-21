// SPDX-License-Identifier: MIT

pragma solidity ^0.8.24;

import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";

/**
 * @title RebaseToken
 * @author George Gorzhiyev
 * @notice This is to follow along with the "Cross Chain Rebase Token" lesson on Cyfrin Updraft.
 * @notice This is a cross-chain rebase token that incentivizes users to deposit into a vault and gain interest in rewards.
 * @notice The interest rate in the smart contract can only decrease.
 * @notice Each user will have their own interest rate that is the global interest rate at the time of deposit.
 */
contract RebaseToken is ERC20 {
    /*==================== ERRORS =============================*/
    error RebaseToken__InterestRateCanOnlyDecrease(uint256 currentInterestRate, uint256 newInterestRate);

    /*==================== EVENTS =============================*/
    event InterestRateSet(uint256 indexed newInterestRate);

    /*==================== STATE VARIABLES ====================*/
    uint256 private s_interestRate = 5e10;
    mapping(address => uint256) private s_userInterestRate;
    mapping(address => uint256) private s_userLastUpdatedTimestamp;
    uint256 private PRECISION_FACTOR = 1e18;

    /*==================== FUNCTIONS ==========================*/
    constructor() ERC20("Rebase Token", "RBT") {}

    /**
     * @notice Set the interest rate for the contract.
     * @param _newInterestRate The new interest rate to set.
     * @dev The interest rate can only decrease.
     */
    function setInterestRate(uint256 _newInterestRate) external {
        if (_newInterestRate < s_interestRate) {
            revert RebaseToken__InterestRateCanOnlyDecrease(s_interestRate, _newInterestRate);
        }

        s_interestRate = _newInterestRate;
        emit InterestRateSet(_newInterestRate);
    }

    /**
     * @notice Mint the user tokens when they deposit into the vault.
     * @param _to The user to mint the tokens to.
     * @param _amount The amount of tokens to mint to the user.
     */
    function mint(address _to, uint256 _amount) external {
        _mintAccruedInterest(_to);
        s_userInterestRate[_to] = s_interestRate;
        _mint(_to, _amount);
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

    function _mintAccruedInterest(address _user) internal {
        // (1) find their current balance of Rebase tokens that have been minted by the user -> principal balance
        // (2) calculate their current balance including any interest -> balanceOf
        // calculate the number of tokens that need to be minted to the user > (2) - (1)
        // call _mint to mint tokens of the user
        // set the users last time stamp
        s_userLastUpdatedTimestamp[_user] = block.timestamp;
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
