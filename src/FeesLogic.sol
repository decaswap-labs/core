// SPDX-License-Identifier: MIT

pragma solidity ^0.8.20;

// import "./lib/LPDeclaration.sol";
import "./interfaces/pool/IPoolActions.sol";
import "./interfaces/pool-logic/IPoolLogicActions.sol";
import "./interfaces/IFeesLogic.sol";
import "./Pool.sol";

import {console} from "forge-std/Test.sol";

contract FeesLogic is IFeesLogic/**, ReentrancyGuard*/ {
    // using LPDeclaration for LPDeclaration.Declaration;
    Pool public poolContract;

    /**
     * @dev poolLpDeclarations pool address to LP address to LPDeclaration structs.
     * @dev poolEpochFees pool address to array of epoch fees.
     * @dev poolEpochCounter returns the epoch value for a pool.
     * @dev poolEpochPDepth pool address to epoch to pDepth.
     * @dev instaBotFees pool to bot address to fees accumulated during the execution of streams.
     * 
     * @dev pools array of pool addresses.
     * 
     * @dev POOL_ADDRESS address of the pool contract.
     * @dev POOL_LOGIC_ADDRESS address of the pool logic contract.
     * @dev DECA_ADDRESS address of the DECA token contract.
     * @dev BOT_FEE_BPS bot fee basis points.
     * @dev LP_FEE_BPS LP fee basis points.
     * @dev GLOBAL_FEE_PERCENTAGE global fee percentage.
     * @dev POOL_LP_FEE_PERCENTAGE pool LP fee percentage.
     * @dev DECA_FEE_PERCENTAGE DECA fee percentage.
     * 
     * @dev all storage should be migrated to the Pool contract
     */

    /** 
     * @dev mappings for the LP Declaration
    */
    mapping(address => mapping(address => uint32[])) public poolLpEpochs;
    mapping(address => mapping(address => uint32[])) public poolLpPUnits;
    mapping(address => mapping(uint32 => uint256)) public poolEpochCounterFees;
    mapping(address => mapping(uint32 => uint256)) public poolEpochCounterFeesHistory;
    mapping(address => uint32) public poolEpochCounter;
    mapping(address => mapping(uint32 => uint32)) public poolEpochPDepth;
    mapping(address => mapping(address => uint256)) public instaBotFees;

    address[] public pools;

    address public override POOL_ADDRESS;
    address public override POOL_LOGIC_ADDRESS;
    address public override DECA_ADDRESS;
    address public override REWARD_TOKEN_ADDRESS;
    uint256 public override BOT_FEE_BPS = 5;
    uint256 public override LP_FEE_BPS = 15;
    uint256 public override GLOBAL_FEE_PERCENTAGE = 45;
    uint256 public override POOL_LP_FEE_PERCENTAGE = 45;
    uint256 public override DECA_FEE_PERCENTAGE = 10;

    constructor (address _poolAddress, address _poolLogicAddress) {
        POOL_ADDRESS = _poolAddress;
        POOL_LOGIC_ADDRESS = _poolLogicAddress;
    }

    fallback() external {
        revert("Invalid function call");
    }

    receive() external payable {
        revert("Invalid function call");
    }

    /**
     * @dev Initializes a new pool.
     * @param pool The address of the pool to initialize.
     */
    function proxyInitPool(address pool) external {
        pools.push(pool);
        poolEpochCounter[pool] = 0;
    }

    /**
     * @dev Simulates the execution of a swap stream for a pool.
     * @param pool The address of the pool.
     * @param amount The amount to swap.
     */
    function proxyExecuteSwapStream(address pool, uint32 amount) external {
        uint32 epoch = poolEpochCounter[pool];
        uint256 lpAmountToDebit = (amount * 15) / 10000;
        poolEpochCounterFees[pool][epoch] += lpAmountToDebit; 
        uint256 botAmountToDebit = (amount * 5) / 10000;
        instaBotFees[pool][msg.sender] += botAmountToDebit;
    }

    /**
     * @dev Executes a liquidity stream for a pool.
     * @param pool The address of the token being debited.
     * @param amount The amount of fee being taken from the stream.
     */
    function proxyExecuteLiquidityStream(address pool, uint256 amount, uint32 pUnits, address liquidityProvider, bool isAdd) external returns(uint256) {
        _endEpoch(pool); /**@audit in reality this should be called after the beginning of each looped and/or
                                         multithreaded run of bot logic add and remove liquidity executions.  
                                             it is included here to simulate stream by stream adds.
                                                 the `endEpoch()` functionality embeds this logic 
                                                     for external calls*/
        uint32 epoch = poolEpochCounter[pool];
        uint256 amountToDebit = ((amount * 5) / 10000); //take 5BPS on the amountIn calculation
        instaBotFees[pool][msg.sender] += amountToDebit;
        if (poolEpochPDepth[pool][epoch] == 0) {
            uint32 oldPDepth = poolEpochPDepth[pool][epoch - 1];
            poolEpochPDepth[pool][epoch] = pUnits + oldPDepth;
        } else if (!isAdd) {
            poolEpochPDepth[pool][epoch] -= pUnits;
        } else {
            poolEpochPDepth[pool][epoch] += pUnits;
        }
        if (poolLpEpochs[pool][liquidityProvider].length == 0) {
            _createLpDeclaration(liquidityProvider, pool, pUnits);
        } else {
            _updateLpDeclaration(liquidityProvider, pool, pUnits, isAdd);
        }
        // instaBotFees[pool][msg.sender] += amountToDebit;
        // claimAccumulatedBotFees(pool);
        return amount - amountToDebit; //auto truncation in division operation means amoun returned is always as underestimate, and lp's benefit from the dust remaining
    }

    /**
     * @dev claimAccumulatedBotFees 
     *          called by the bot to claim their fees. 
     *          the function reads the accumulation of fees in the bot's declaration
     *          and this sum is transferred instantly to the bot
     *          in the tokens they have executed streams for.
     * 
     *          a safety factor is taken into consideration such that,
     *          in the event that there is a network faillure part way
     *          through a stream execution, the bot can claim their fees 
     *          by directly calling this function.
     * 
     *          N.B. this is to be called internally once at the end of each streaming multithreaded loop,
     *          in each of addLiquidity, removeLiquidity, and swap stream execution processes
     * 
     * @param _pool the token from which the bot has executed streams   
     */
    function claimAccumulatedBotFees(address _pool) external /**onlyRouter*/ {
        uint256 fee = instaBotFees[_pool][msg.sender];
        require(fee > 0, "No fees available");
        instaBotFees[_pool][msg.sender] = 0;
        // IPoolActions(POOL_ADDRESS).transferTokens(_pool, msg.sender, fee);
    }

    /**
     * @dev _createLpDeclaration
     *          should be called on the EOA called execution on the first stream of addLiquidity for both A and D
     * @param _liquidityProvider the ethereum address of the LP
     * @param _pool the token pool which the LP is providing liquidity to
     * @param _pUnits the amount of D to be taken from the stream
     * 
     * N.B Each LP has only one declaration for each pool they have liquidity in
     * N.B The address for the global pool will be represented as the result of abi.encode of the incoming token address 
     */
    function createLpDeclaration(address _liquidityProvider, address _pool, uint32 _pUnits) external {
        _createLpDeclaration(_liquidityProvider, _pool, _pUnits);
    }

    /**
     * @dev _updateLpDeclaration
     *          should be called on the execution of adding or removing liquidity
     * @param _liquidityProvider the ethereum address of the LP
     * @param _pool the token pool which the LP is providing liquidity to or taking liquidity from
     * @param _pUnits the delta of pUnits in the stream execution
     * @param isAdd a boolean to determine if the stream is an add (true) or withdraw (false)
     */
    function updateLpDeclaration(address _liquidityProvider, address _pool, uint32 _pUnits, bool isAdd) external {
        _updateLpDeclaration(_liquidityProvider, _pool, _pUnits, isAdd);
    }

    /**
     * @dev _debitLpFeesFromStream 
     *          should be called on the execution of amount out calculations and price execution
     *          taking 15BPS of the amount out
     * @param pool address of the token which the fees are accumulated in
     * @param feeInA the amount of A to be taken from the stream
     */
    function debitLpFeesFromSwapStream(address pool, uint256 feeInA) external {
        _debitLpFeesFromSwapStream(pool, feeInA);
    }

    /**
     * @dev _debitBotFeesFromStream 
     *          should be called on the execution of amount out calculations and price execution
     *          taking 5BPS of the amount out
     * @param pool the address of the pool whose epoch is being incremented
     * @param fee the amount of D to be taken from the stream
     */
    function debitBotFeesFromSwapStream(address pool, uint256 fee) external {
        _debitBotFeesFromSwapStream(pool, fee);
    }

    // /**
    //  * @dev _debitBotFeesFromLiquidity
    //  *          should be called on the execution of amount out calculations and price execution
    //  *          taking 5BPS of the amount in in D
    //  * @param _pool the amount of D to be taken from the stream
    //  * @param _amount the amount of D to be taken from the stream
    //  */
    // function debitBotFeesFromLiquidityStream(address _pool, uint256 _amount) external {
    //     _debitBotFeesFromLiquidityStream(_pool, _amount);
    // }
    // function _debitBotFeesFromLiquidityStream(address _pool, uint256 _amount) internal {
    //     uint256 existingAccumulation = instaBotFees[_pool][msg.sender];
    //     instaBotFees[_pool][msg.sender] += _amount;
    //     uint256 newAccumulation = instaBotFees[_pool][msg.sender];
    // }

    /**
     * @dev Updates the pool address.
     * @param poolAddress The new pool address.
     */
    function updatePoolAddress(address poolAddress) external override {
        POOL_ADDRESS = poolAddress;
        emit PoolAddressUpdated(POOL_ADDRESS, poolAddress);
    }

    /**
     * @dev Updates the pool logic address.
     * @param _poolLogicAddress The new pool logic address.
     */
    function updatePoolLogicAddress(address _poolLogicAddress) external override {
        POOL_LOGIC_ADDRESS = _poolLogicAddress;
    }

    /**
     * @dev claimLPAllocation 
     *          called by an LP to claim their allocation of fees. 
     *          the function iterates over the spread of epochs in the LP's declaration
     *          and calculates the allocation of fees for each epoch by taking the fractional
     *          allocation according to the pDepth. 
     * 
     *          At the end of the iteration, the values are deleted from storage, the currentEpoch value 
     *          and corresponding pUnits held by the LP are re-cached, and the sum is transferred 
     *          instantly to the LP in the tokens they have provided liquidity for.
     * 
     * @param pool the address of the pool where the LP has liquidity
     * @param liquidityProvider the address of the LP
     */

    function claimLPAllocation(address pool, address liquidityProvider) external override payable returns (uint256) {
        // @audit this needs to be built to find which kind of provider the calle is, and return the according portion
        uint256 allocation = _consumeLPAllocation(pool, liquidityProvider);
        return allocation;
        // IPoolActions(POOL_ADDRESS).transferTokens(pool, liquidityProvider, allocation);
    }

    /**
     * @dev _consumeLPAllocation
     * 
     * @param pool pool for which the claimant is claiming fees
     * @param liquidityProvider liquidity provider
     */

    function _consumeLPAllocation(address pool, address liquidityProvider) internal returns (uint256 allocation) {
        uint32 currentEpoch = poolEpochCounter[pool];
        allocation = _doctorBob(pool, liquidityProvider, currentEpoch);
        _resetDeclaration(pool, liquidityProvider, currentEpoch);
        // IPoolActions(POOL_ADDRESS).transferTokens(pool, liquidityProvider, accumulator);
    }

    function _resetDeclaration(address pool, address liquidityProvider, uint32 currentEpoch) internal {
        uint32 latestPUnits = poolLpPUnits[pool][liquidityProvider][poolLpPUnits[pool][liquidityProvider].length - 1];
        delete poolLpEpochs[pool][liquidityProvider];
        poolLpEpochs[pool][liquidityProvider].push(currentEpoch);
        delete poolLpPUnits[pool][liquidityProvider];
        poolLpPUnits[pool][liquidityProvider].push(latestPUnits);
    }

    function _createLpDeclaration(address _liquidityProvider, address _pool, uint32 _pUnits) internal {
        uint32 currentEpoch = poolEpochCounter[_pool];
        // lets instead just populate the mappings for the two values of interest
        // poolEpochPDepth[_pool][currentEpoch] += _pUnits;
        poolLpEpochs[_pool][_liquidityProvider].push(currentEpoch);
        poolLpPUnits[_pool][_liquidityProvider].push(_pUnits);
        emit LpDeclarationCreated(_liquidityProvider);
    }

    /**
     * @dev _doctorBob
     *          epoch based rewards,
     *          specifically adapted to operate in a streaming swap environment.
     *          the algorithm iterates over two arrays of epochs and pUnits
     *          wrt the calling liquidity provider and reads the relative portion 
     *          from the state of the contract.
     * 
     *          the cost is approximately 25k gas for the call + 6k gas 
     *          for each epoch iterated.
     * 
     * @param pool pool adddress
     * @param lp claimant
     *
     */
    function _doctorBob(address pool, address lp, uint32 currentEpoch) internal view returns (uint256) {
        // @audit need to manage the state of old epochFees to avoid over withdrawal potential
        uint32[] memory lpEpochs = poolLpEpochs[pool][lp];
        uint32[] memory lpPUnits = poolLpPUnits[pool][lp];

        if (lpPUnits.length == 0 || lpPUnits[lpPUnits.length - 1] == 0) revert InternalError();

        require(lpEpochs[lpEpochs.length - 1] != 0, "No declaration exists");
        require(lpEpochs[0] <= currentEpoch, "Invalid Epoch");
        require(lpEpochs[0] != currentEpoch, "LP's can only process completed epochs");
        
        if (lpEpochs[0] > currentEpoch) {
            revert InternalError();
            // this shouldn't be possible
        }
        uint256 phases = lpEpochs.length;
        uint256 lastIteratedIndex;
        uint256 lastPUnits;
        uint256 accumulator;

        for (uint32 epoch = lpEpochs[0]; epoch < currentEpoch; epoch++) {
            uint256 feeInEpoch;
            uint256 pDepthInEpoch;
            lastPUnits = lpPUnits[lastIteratedIndex];

            if (lpEpochs[lastIteratedIndex] + 1 != epoch + 1) {
                feeInEpoch = poolEpochCounterFees[pool][epoch];
                pDepthInEpoch = poolEpochPDepth[pool][epoch];
                accumulator += (feeInEpoch * lastPUnits) / pDepthInEpoch;
            } else {
                feeInEpoch = poolEpochCounterFees[pool][epoch]; 
                pDepthInEpoch = poolEpochPDepth[pool][epoch];
                accumulator += (feeInEpoch * lastPUnits) / pDepthInEpoch;
                if (phases > lastIteratedIndex + 1) {
                    lastIteratedIndex++;
                    }
                lastPUnits = lpPUnits[lastIteratedIndex];
            }
        }
        uint256 ratio = _resolveTypeOfClaimant(pool, lp);
        // @audit need to handle precision here
        return (accumulator * ratio) / 100;
    }

    function _debitLpFeesFromSwapStream(address _pool, uint256 _feeInA) internal {
        uint32 epoch = poolEpochCounter[_pool];
        uint256 accumulatedFee = poolEpochCounterFees[_pool][epoch];
        accumulatedFee += _feeInA;
        poolEpochCounterFees[_pool][epoch] = accumulatedFee;
    }

    /**
     * @dev _endEpoch
     *          should be called on the iniialisation of each add/remove liquidity bot logic run
     * @param _pool the address of the pool whose epoch is being incremented
     */
    function _endEpoch(address _pool) internal {
        uint32 existingEpoch = poolEpochCounter[_pool];
        poolEpochCounter[_pool]++;
        // uint256 feesAccumulated = poolEpochCounterFees[_pool][existingEpoch];
        // poolEpochCounterFeesHistory[_pool][existingEpoch] = feesAccumulated;
        uint32 oldPDepth = poolEpochPDepth[_pool][existingEpoch];
        poolEpochPDepth[_pool][existingEpoch + 1] = oldPDepth;
    }
    
    /**
     * @dev closeLpDeclaration to be executed on on removal of all liquidity.
     *          note the withdraw functionality claimAllocation is automatically called at the end of function flow,
     *          ensuring that the LP is paid out for the last epoch they had liquidity in. As such, remove liquidity should 
     *          be called before add liquidity.
     *          note this function should only be called on the last stream execution of
     *          remove liquidity. 
     * @param _pool pool where declaration exists
     * @param _liquidityProvider LPs Eth address
     * 
     */
    function _closeLpDeclaration(address _pool, address _liquidityProvider, uint32 currentEpoch, uint32 lastPUnits) internal {
        delete poolLpEpochs[_pool][_liquidityProvider];
        poolLpEpochs[_pool][_liquidityProvider].push(currentEpoch);
        delete poolLpPUnits[_pool][_liquidityProvider];
        poolLpPUnits[_pool][_liquidityProvider].push(lastPUnits);
    }

    function _debitBotFeesFromSwapStream(address _pool, uint256 _fee) internal {
        instaBotFees[_pool][msg.sender] += _fee;
    }

    function _resolveTypeOfClaimant(address pool, address claimant) internal view returns (uint256) {
        if (poolLpEpochs[pool][claimant].length > 0) {
            return POOL_LP_FEE_PERCENTAGE;
        } else if (poolLpEpochs[POOL_ADDRESS][claimant].length > 0) {
            return GLOBAL_FEE_PERCENTAGE;
        } /**else if (claimant == DECA_ADDRESS) {
            return DECA_FEE_PERCENTAGE;
        } @note this needs implementing properly once the DECA token 
        contract is deployed*/ 
        else {
            return 0;
        }
    }

    function _updateLpDeclaration(address _liquidityProvider, address _pool, uint32 _pUnits, bool isAdd) internal {
        // require(poolLpDeclarations[_pool][_liquidityProvider].epochFinish != 1, "Declaration is closed");
        /**
         * @audit checks should be made first to ensure streamCount != streamCountRemaining, 
         * and also to ensure that amount is of a certai n value, ensuring that executing this
         * addLiquidity stream is meant to provide pUnits as further layers of security
         */
        uint32 currentEpoch = poolEpochCounter[_pool];
        uint32[] storage lpEpochs = poolLpEpochs[_pool][_liquidityProvider];
        lpEpochs.push(currentEpoch);
        if (!isAdd) {
            uint32[] memory oldUnitsArray = poolLpPUnits[_pool][_liquidityProvider];
            uint32 newUnits = oldUnitsArray[oldUnitsArray.length - 1] - _pUnits;            
            if (newUnits == 0) {
                // _claimLPAllocation(_pool, _liquidityProvider);
                _closeLpDeclaration(_pool, _liquidityProvider, currentEpoch, newUnits);
            } else {
            poolLpPUnits[_pool][_liquidityProvider].push(newUnits);
            }
        } else {
            uint32[] memory oldUnitsArray = poolLpPUnits[_pool][_liquidityProvider];
            uint32 originalAllocation = oldUnitsArray[oldUnitsArray.length - 1];
            uint32 newUnits = originalAllocation + _pUnits;
            poolLpPUnits[_pool][_liquidityProvider].push(newUnits);
            // poolEpochPDepth[_pool][currentEpoch] += _pUnits; 
            // @audit this needs to be effectively handled when integrating into numerous stream executions
        }
    }
}
