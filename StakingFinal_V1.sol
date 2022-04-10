// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/security/Pausable.sol";


contract StakingTokenDFH is Pausable,Ownable {
    struct userInfoStaking {
        bool isActive;
        uint256 amount;
        uint256 startTime;
        uint256 endTime;
        uint256 stakeOptions;
        uint256 fullLockedDays;
        uint256 valueAPY;
        uint256 reward;
    }

    struct OptionsStaking{
        uint256 lockDays;
        uint256 valueAPY;
        uint256 maxPool;
        uint256 curPool;
    }

    struct userInfoTotal{
        uint256 totalStaked; 
        uint256 totalReward;
    }

    ERC20 public token;
    mapping(bytes32 => userInfoStaking) private infoStaking;
    mapping(uint256 => OptionsStaking) private infoOptions;
    mapping(address => userInfoTotal) private infoTotal;

    event UsersStaking(address indexed user, uint256 amountStake, uint256 indexed option, uint256 indexed id);
    event UserUnstaking(address indexed user, uint256 claimableAmountStake, uint256 indexed option, uint256 indexed id);
    event UserReward(address indexed user, uint256 claimableReward, uint256 indexed option, uint256 indexed id);

    uint256 public endTimeEvent;
    uint256 public lockRewardDuration = (10 minutes);
    uint256 public totalStaked = 0;
    uint256 public totalClaimed = 0;

    constructor(ERC20 _token) {
        token = _token;
        endTimeEvent = 1712202161; // default end time on Thu Apr 04 2024
    }

    function setOptionsStaking(
        uint256[] memory _optionInfoDay, 
        uint256[] memory _optionInfoAPY,
        uint256[] memory _optionInfoMaxPool
    ) public onlyOwner{
        require(_optionInfoDay.length == _optionInfoAPY.length, "SetOptions: The inputs have the same length");
        require(_optionInfoDay.length == _optionInfoMaxPool.length, "SetOptions: The inputs have the same length");

        for(uint256 i=0; i < _optionInfoDay.length; i++){
            OptionsStaking memory info = OptionsStaking(_optionInfoDay[i], _optionInfoAPY[i], _optionInfoMaxPool[i], 0);
            infoOptions[i] = info;
        }
    }

    function setEndTime (uint256 endTime) public onlyOwner {
        endTimeEvent = endTime;
    }

    function setLockRewardDuration (uint256 _lockRewardDuration) public onlyOwner {
        lockRewardDuration = _lockRewardDuration;
    }

    function viewOptionsStaking(uint256 _ops) public view returns(uint256, uint256, uint256, uint256){
        return (infoOptions[_ops].lockDays, infoOptions[_ops].valueAPY, infoOptions[_ops].maxPool, infoOptions[_ops].curPool);
    }

    function pause() public onlyOwner {
        _pause();
    }

    function unpause() public onlyOwner {
        _unpause();
    }

    function userStake(uint256 _amountStake, uint256 _ops, uint256 _id) public whenNotPaused {
        bytes32 _value = keccak256(abi.encodePacked(_msgSender(), _ops, _id));
        require(infoStaking[_value].isActive == false, "UserStake: Duplicate id");
        uint256 _curPool = infoOptions[_ops].curPool + _amountStake;
        require(_curPool <= infoOptions[_ops].maxPool, "UserStake: Max Amount");
        require(block.timestamp <= endTimeEvent,"UserStake: Event Over Time");

        token.transferFrom(msg.sender, address(this), _amountStake);

        uint256 _lockDay =  infoOptions[_ops].lockDays;
        uint256 _apy = infoOptions[_ops].valueAPY;
        uint256 _reward = _calcRewardStaking(_apy,_lockDay,_amountStake);
        if(_ops == 0) {
            _reward = 0;
        }

        uint256 _endTime = block.timestamp + _lockDay;
        userInfoStaking memory info =
            userInfoStaking(
                true, 
                _amountStake, 
                block.timestamp,
                _endTime, 
                _ops,
                _lockDay,
                _apy,
                _reward
            );
        infoStaking[_value] = info;
        infoOptions[_ops].curPool = _curPool;
        totalStaked = totalStaked + _amountStake;
        emit UsersStaking(msg.sender, _amountStake, _ops, _id);

        userInfoTotal storage infoTotals  = infoTotal[_msgSender()];
        infoTotals.totalStaked = infoTotals.totalStaked + _amountStake;
        infoTotals.totalReward = infoTotals.totalReward + _reward;
    }

    function estRewardAmount(uint256 _apy, uint256 _lockDay, uint256 _amount)
        public
        pure
        returns(uint256)
    {
        return _calcRewardStaking(_apy, _lockDay, _amount);
    }

    function _calcRewardStaking(uint256 _apy, uint256 _lockDay, uint256 _amountStake)
        internal
        pure
        returns(uint256)
    {
        uint256 _result = (_apy * (10**18) / 100)*_lockDay*_amountStake;
        return (_result / 365) / (10**18);
    }

    function userUnstake(uint256 _ops, uint256 _id) public {
        bytes32 _value = keccak256(abi.encodePacked(_msgSender(), _ops,_id));
        uint256 claimableAmount = _calcClaimableAmount(_value);
        require(claimableAmount > 0, "Unstaking: Nothing to claim");

        token.transfer(msg.sender,claimableAmount);
        emit UserUnstaking(msg.sender, claimableAmount, _ops, _id);

        userInfoStaking storage info = infoStaking[_value];
        info.endTime = block.timestamp;
        info.isActive = false;
        if (_ops == 0) {
            uint256 _lockDay = (block.timestamp - info.startTime) / (infoOptions[0].lockDays);
            uint256 _reward = _calcRewardStaking(info.valueAPY,_lockDay,info.amount);
            info.reward = _reward;
        }
        info.amount = 0;
    }

    function _calcClaimableAmount(bytes32 _value)
        internal
        view 
        returns(uint256 claimableAmount)
    {
        userInfoStaking memory info = infoStaking[_value];
        if(!info.isActive) return 0;
        if(block.timestamp < info.endTime) return 0;
        claimableAmount = info.amount;
    }

    function claimReward(uint256 _ops, uint256 _id) public{
        bytes32 _value = keccak256(abi.encodePacked(_msgSender(), _ops,_id));
        uint256 _claimableReward = _calcReward(_value);
        require(_claimableReward > 0, "Reward: Nothing to claim");
        token.transfer(msg.sender,_claimableReward);

        userInfoStaking storage info = infoStaking[_value];
        info.reward = 0;

        totalClaimed = totalClaimed + _claimableReward;
        emit UserReward(msg.sender, _claimableReward, _ops, _id);
    }

    function _calcReward(bytes32 _value)
        internal
        view
        returns(uint256 claimableReward)
    {
        userInfoStaking memory info = infoStaking[_value];
        uint256 releaseTime = info.endTime + lockRewardDuration;
        if(block.timestamp < releaseTime) return 0;
        claimableReward = info.reward;
    }

    function getInfoUserTotal(address account)
        public 
        view 
        returns (uint256,uint256) 
    {
        userInfoTotal memory info = infoTotal[account];
        return (info.totalStaked,info.totalReward);
    }

    function getInfoUserStaking(
        address account,
        uint256 _ops,
        uint256 _id
    ) 
        public
        view 
        returns (bool, uint256, uint256, uint256, uint256, uint256, uint256, uint256)
    {
        bytes32 _value = keccak256(abi.encodePacked(account, _ops,_id));
        userInfoStaking memory info = infoStaking[_value];
        return (
            info.isActive,
            info.amount, 
            info.startTime,
            info.endTime,
            info.stakeOptions,
            info.fullLockedDays,
            info.valueAPY,
            info.reward
        );
    }

    event Received(address, uint);
    receive () external payable {
        emit Received(msg.sender, msg.value);
    } 

}

/**
* Staking Options Demo:
* [60,180,360,540,1080]
* [60,150,200,300,500]
* [1000000,1000000,1000000,1000000,1000000]
*/
