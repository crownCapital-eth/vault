pragma solidity 0.8.4;
// SPDX-License-Identifier: MIT

import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/security/Pausable.sol";
import "./CrownToken.sol";
import "./Vault.sol";

/// @title Crown Capital Single LP Farm
/// @author sters.eth
/// @notice Contract stakes Crown tokens and pays yield in Crown Tokens
contract Farm is Ownable, Pausable {

    string public name = "Crown Capital Farm";

    /// @dev Array of active stakers
    address[] public stakers;

    /// @dev last time farm yield was updated
    uint256 public startTime;

    /// @dev the total amount of tokens staked in contract
    uint256 public totalStaked;

    /// @dev the time the farm was deployed
    uint256 public farmStartTime;

    /// @dev addresses are mapped to a boolean indicating if the address is staking
    mapping(address => bool) public isStaking;

    /// @dev addresses are mapped to a yield available to claim by the address
    mapping(address => uint256) public crownYield;

    /// @dev addresses are mapped to the amount has Staked
    mapping(address => uint256) public stakingBalance;

    event Stake(address indexed from, uint256 amount);
    event Unstake(address indexed from, uint256 amount);
    event YieldWithdraw(address indexed to, uint256 amount);

    Vault vault;
    CrownToken crownToken;
    constructor(address tokenAddress, address vaultAddress) {
        crownToken = CrownToken(tokenAddress);
        vault = Vault(vaultAddress);
        farmStartTime = block.timestamp;
        totalStaked=0;
    }

    /** @dev allows the user to stake crown tokens when the contract is not paused.
  * @param amountToStake the amount of crown tokens the user wants to stake
  */
    function stake(uint256 amountToStake) public whenNotPaused {
        require(
            amountToStake > 0,
            "You cannot stake zero tokens.");
        updateYield();

        (bool sent) = crownToken.transferFrom(msg.sender, address(this), amountToStake);
        require(sent, "Failed to transfer tokens from user to Farm");

        if(isStaking[msg.sender] == false){
            isStaking[msg.sender] = true;
            stakers.push(msg.sender);
        }
        stakingBalance[msg.sender] += amountToStake;
        totalStaked+=amountToStake;
        startTime = block.timestamp;
        emit Stake(msg.sender, amountToStake);
    }

    /** @dev allows the user to unstake crown tokens. Unstaking cannot be paused.
  * @param amountToUnstake the amount of crown tokens the user wants to unstake
  */
    function unstake(uint256 amountToUnstake) public  {
        require(
            amountToUnstake > 0,
            "You cannot unstake zero tokens.");
        require(
            isStaking[msg.sender] = true &&
        stakingBalance[msg.sender] >= amountToUnstake,
            "Requested withdraw greater than staking balance."
        );
        if(stakers.length > 0){
            updateYield();
        }

        uint256 balTransfer = 0;
        balTransfer = amountToUnstake;
        stakingBalance[msg.sender] -= balTransfer;
        totalStaked-= balTransfer;

        if(stakingBalance[msg.sender] == 0){
            if(stakers.length == 1){
                delete stakers; }
            else {
                for (
                    uint256 stakersIndex = 0;
                    stakersIndex < stakers.length;
                    stakersIndex++
                ) {
                    if(msg.sender == stakers[stakersIndex]){
                        removeAddress(stakersIndex);
                    }
                }
            }
            isStaking[msg.sender] = false;
        }

        (bool sent) = crownToken.transfer(msg.sender, balTransfer);
        require(sent, "Failed to withdraw tokens");

        emit Unstake(msg.sender, balTransfer);
    }

    /// @dev allows the user to withdraw crown tokens from yield when the farm is not paused.
    function withdrawYield() public whenNotPaused {
        if (isStaking[msg.sender]){
            updateYield();
        }
        uint256 toTransfer=0;
        toTransfer = crownYield[msg.sender];
        crownYield[msg.sender] = 0;

        require(
            toTransfer > 0,
            "Nothing to withdraw"
        );

        uint256 farmBalance = crownToken.balanceOf(address(this));
        require(farmBalance >= toTransfer,
            "Insuffcient funds in Farm Contract");

        (bool sent) = crownToken.transfer(msg.sender, toTransfer);
        require(sent, "Failed to withdraw Tokens");

        emit YieldWithdraw(msg.sender, toTransfer);
    }

    /// @dev updates the yield of each user. Sends crown to the farm.
    function updateYield() private {
        vault.sendToFarm();
        for (
            uint256 stakersIndex = 0;
            stakersIndex < stakers.length;
            stakersIndex++
        ) {
            address staker = stakers[stakersIndex];
            uint256 totalYield = 0;
            totalYield = calculateUserTotalYield(staker);
            crownYield[staker] = totalYield;
        }
        startTime = block.timestamp;
    }

    /** @dev calculates a users total yield
  *  @param staker address of staker to check
  *  @return totalYield the total yield available to withdraw (when not paused)
  */
    function calculateUserTotalYield(address staker) public view returns(uint256) {
        uint256 secondsPassed = calculateYieldTime() * 10**18;
        uint256 stakingPercent = userStakingPercent(staker);
        uint256 farmSecondsPerToken = vault.getFarmSecondsPerToken(address(this));
        uint256 newYield = (stakingPercent * secondsPassed) / (farmSecondsPerToken);
        uint256 totalYield = crownYield[staker] + newYield;
        return totalYield;
    }

    /// @dev returns user staking percent of totalStaked
    function userStakingPercent(address staker) public view returns(uint256) {
        uint256 stakingPercent = 0;
        if(isStaking[staker] == true){
            stakingPercent = (stakingBalance[staker]*10**18) / totalStaked;
        }
        return stakingPercent;
    }

    /// @dev returns seconds passed since yield last updated
    function calculateYieldTime() public view returns(uint256){
        uint256 totalTime = 0;
        uint256 end = block.timestamp;
        totalTime = end - startTime;
        return totalTime;
    }

    /// @dev deletes a staker from the stakers list
    function removeAddress(uint index) private {
        stakers[index] = stakers[stakers.length - 1];
        stakers.pop(); // Remove the last element
    }

    /// @dev returns array of addresses with active stakers
    function getStakers() public view returns (address[] memory) {
        return stakers;
    }

    /// @dev returns boolean of true if the user is actively staking
    function isUserStaking(address staker) public view returns(bool) {
        return isStaking[staker];
    }

    /// @dev returns the amount of tokens staked by user
    function getUserBalance(address staker) public view returns(uint256) {
        return stakingBalance[staker];
    }

    /** @dev returns the amount of yield the staker
  * @param staker address of user to request yield
  */
    function getCrownYield(address staker) public view returns(uint256) {
        return crownYield[staker];
    }

}