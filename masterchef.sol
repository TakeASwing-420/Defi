//SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import "./token1.sol";

contract MasterChefV1 is Ownable, ReentrancyGuard {
    using SafeERC20 for IERC20;

    struct UserInfo {
        uint256 staking_amount;
        uint256 pendingReward;
    }

    struct PoolInfo {
        /*
In a pool, suppose where ETH is staked and DAI is used for rewarding, the liquidity pool token would typically represent a token that represents ownership in the liquidity pool where both ETH and DAI are deposited. This token is usually issued to liquidity providers as a receipt for their contribution to the pool.

Since ETH and DAI are two different assets, they would be pooled together in a liquidity pool on a decentralized exchange (DEX) such as Uniswap or SushiSwap. Liquidity providers would deposit both ETH and DAI into this pool and receive a token representing their share of the pool, commonly known as a liquidity pool token or LP token.

dev@                       General Liquidity Pool Token types(3)   [ for ETH/DAI ]
                                    /       |       \
                                   /        |        \
*                         liquidity pool    |         \
*                            token       staking     reward
*                          (Mylpcustom)    token      token
*                                           (ETH)      (DAI)

! So, in this case, the liquidity pool token would be the token representing ownership in the ETH-DAI liquidity pool on a DEX. This token is often referred to as something like "UNI-V2" or "SUSHI-LP", depending on the platform. it is neither ETH nor DAI .
*/
        IERC20 lpToken; //! But in this tutorial, for simplicity it is assumed that the lptoken is same as the staking token. 
        uint256 allocPoint;//* In this case, simply the priority value for a particular pool over other pools. The more points, the better is to invest in this pool.
        uint256 lastRewardBlock;//* The algorithm basically uses some calculation based on no. of in-between blocks after the last and current transcation.
        uint256 rewardTokenPerShare;  //* The reward rate of a certain pool at that particular moment to any user who is unstaking tokens. After that, it will update itself.
    }

    MyToken1 public rewardtoken; //* In a good practical scenario, the staking token and reward token should also be separate members of PoolInfo struct but here we are assuming that all pools emit same ERC token as reward .
    address public dev;
    uint256 public rewardtokenPerBlock;

    mapping(uint256 => mapping(address => UserInfo)) public userInfo;

    PoolInfo[] public poolInfo;
    uint256 public totalAllocation = 0;
    uint256 public startBlock;
    uint256 public BONUS_MULTIPLIER;

    constructor(
        MyToken1 _mtk,
        address _dev,
        uint256 _mtkPerBlock,
        uint256 _startBlock,
        uint256 _multiplier
    ) Ownable(_dev) ReentrancyGuard(){
        rewardtoken = _mtk;
        dev = _dev;
        rewardtokenPerBlock = _mtkPerBlock;
        startBlock = _startBlock;
        BONUS_MULTIPLIER = _multiplier;

        poolInfo.push(
            PoolInfo({
                lpToken: _mtk,
                allocPoint: 1000,
                lastRewardBlock: _startBlock,
                rewardTokenPerShare: 0
            })
        );
        totalAllocation = 1000;
    }
    
    event Deposit(address indexed user, uint256 indexed pid, uint256 amount);
    event Withdraw(address indexed user, uint256 indexed pid, uint256 amount);
    event EmergencyWithdraw(address indexed user, uint256 indexed pid, uint256 amount);

    modifier validatePool(uint256 _pid) {
        require(_pid < poolInfo.length, "Pool Id Invalid");
        _;
    }

    function getMultiplier(uint256 _from, uint256 _to)
        public
        view
        returns (uint256)
    {
        return (_to - _from) * BONUS_MULTIPLIER;
    }

    function updateBonusMultiplier(uint256 multiplierNumber) public onlyOwner {
        BONUS_MULTIPLIER = multiplierNumber;
    }

    function checkPoolDuplicate(IERC20 _lpToken) public view {
        uint256 length = poolInfo.length;
        for (uint256 _pid = 0; _pid < length; _pid++) {
            require(poolInfo[_pid].lpToken != _lpToken, "Pool Already Exists");
        }
    }

    //? What are the scenarios when you will call the below function....
    /*
    dev   when adding a new pool or changing allocation points for an existing pool
    */ 
    function reAdjust_allocation_points_for_every_single_pool() internal {
        uint256 length = poolInfo.length;
        uint256 drop_points = totalAllocation / 13;
        uint256 totalsum = 0;
        for (uint256 pid = 0; pid < length; ++pid) {
            poolInfo[pid].allocPoint -= drop_points*(length-pid);
            //! Always incentivize the latest added pools... that's the motto
            totalsum += drop_points*(length-pid);
        }
        totalAllocation -= totalsum;
    }

    function add_a_new_pool(uint256 _allocPoint, IERC20 _lpToken) public onlyOwner {
        checkPoolDuplicate(_lpToken);
        uint256 lastRewardBlock = block.number > startBlock ? block.number : startBlock;
        totalAllocation += _allocPoint;
        poolInfo.push(
            PoolInfo({
                lpToken: _lpToken,
                allocPoint: _allocPoint,
                lastRewardBlock: lastRewardBlock,
                rewardTokenPerShare: 0
            })
        );
        reAdjust_allocation_points_for_every_single_pool();
    }

      function change_alloc_for_a_particular_pool(uint256 _pid, uint256 _allocPoint) public onlyOwner validatePool(_pid) {
        uint256 prevAllocPoint = poolInfo[_pid].allocPoint;
        if (prevAllocPoint != _allocPoint) {
            poolInfo[_pid].allocPoint = _allocPoint;
            totalAllocation = totalAllocation - prevAllocPoint + _allocPoint;
            reAdjust_allocation_points_for_every_single_pool();
        }
    }

    function update_Pool_while_staking_or_destaking(uint256 _pid) private validatePool(_pid) {
        PoolInfo storage pool = poolInfo[_pid];
        if (block.number <= pool.lastRewardBlock) {
            return;
        }
        uint256 lpSupply = pool.lpToken.balanceOf(address(pool.lpToken));
        if (lpSupply == 0){
            pool.lastRewardBlock = block.number;
            return;
        }
        uint256 multiplier = getMultiplier(pool.lastRewardBlock, block.number);
        uint256 totalReward = (multiplier * rewardtokenPerBlock * pool.allocPoint) / totalAllocation;

    //? If you don't understand the difference between variables {pool.allocpoint} and {lpSupply}...  :)
    /*
    Explanation with Context:

    * Allocation Points (allocPoint): Imagine you have multiple pools in a yield farming system. Each pool might represent different token pairs (e.g., [ETH for staking / DAI for rewarding], [USDT for staking/DAI for rewarding]). To incentivize users to provide liquidity to certain pools, you allocate points to each pool. For instance, Pool A has 1000 allocation points, and Pool B has 500 allocation points. This means Pool A will receive twice the rewards of Pool B.

    * LP Supply (lpSupply): Within Pool A, if there are 10,000 LP tokens staked by all users, and you have staked 1,000 LP tokens, you own 10% of the lpSupply. The rewards distributed to Pool A will then be further divided among all stakers based on their share of the total lpSupply.
    */
        rewardtoken.tokenmint(address(rewardtoken), totalReward);
        pool.rewardTokenPerShare += (totalReward * 1e12) / lpSupply; 
        //! In the previous line, When rewards are distributed to the pool (in the updatePool function), the total reward tokens earned by the pool are divided by the total number of LP tokens (lpSupply). This gives the reward tokens earned per LP token (totalReward / lpSupply) for unstaking in that moment.

        pool.lastRewardBlock = block.number;
    }
    
    function stake(uint256 _pid, uint256 _amount) public validatePool(_pid) {
    PoolInfo storage pool = poolInfo[_pid];
    UserInfo storage user = userInfo[_pid][msg.sender];
    update_Pool_while_staking_or_destaking(_pid);
    if (user.staking_amount > 0) {
        uint256 pending = (user.staking_amount * pool.rewardTokenPerShare) / 1e12 - user.pendingReward;
        if(pending > 0) {
            rewardtoken.safeTransfer(msg.sender, pending);
        }
    }
    if (_amount > 0) {
        pool.lpToken.transferFrom(address(msg.sender), address(pool.lpToken) , _amount);
        user.staking_amount += _amount;
    }
    user.pendingReward = (user.staking_amount * pool.rewardTokenPerShare) / 1e12;
    emit Deposit(msg.sender, _pid, _amount);
}

function autoCompound() public {
    PoolInfo storage pool = poolInfo[0];
    UserInfo storage user = userInfo[0][msg.sender];
    update_Pool_while_staking_or_destaking(0);
    if (user.staking_amount > 0) {
        uint256 pending = (user.staking_amount * pool.rewardTokenPerShare) / 1e12 - user.pendingReward;
        pool.lpToken.transferFrom(address(msg.sender), address(pool.lpToken) , pending);
        if(pending > 0) {
            user.staking_amount += pending;
        }
    }
    user.pendingReward = (user.staking_amount * pool.rewardTokenPerShare) / 1e12;
}

function unstake(uint256 _pid, uint256 _amount) public validatePool(_pid) {
    PoolInfo storage pool = poolInfo[_pid];
    UserInfo storage user = userInfo[_pid][msg.sender];
    require(user.staking_amount >= _amount, "withdraw: insufficient balance");
    update_Pool_while_staking_or_destaking(_pid);
    uint256 pending = (user.staking_amount * pool.rewardTokenPerShare) / 1e12 - user.pendingReward;
    if(pending > 0) {
        rewardtoken.safeTransfer(msg.sender, pending);
    }
    if(_amount > 0) {
        user.staking_amount -=  _amount;
        pool.lpToken.transferFrom(address(pool.lpToken) , address(msg.sender), _amount);
    }
    user.pendingReward = (user.staking_amount * pool.rewardTokenPerShare) / 1e12;
    emit Withdraw(msg.sender, _pid, _amount);
}

function emergencyWithdraw(uint256 _pid) public {
    PoolInfo storage pool = poolInfo[_pid];
    UserInfo storage user = userInfo[_pid][msg.sender];
    pool.lpToken.transferFrom(address(pool.lpToken) , address(msg.sender), user.staking_amount);
    emit EmergencyWithdraw(msg.sender, _pid, user.staking_amount);
    user.staking_amount = 0;
    user.pendingReward = 0;
}

}
