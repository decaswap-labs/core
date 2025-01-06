// SPDX-License-Identifier: MIT

pragma solidity ^0.8.20;

// import "./lib/LPDeclaration.sol";
import "./interfaces/pool/IPoolActions.sol";
import "./interfaces/pool-logic/IPoolLogicActions.sol";
import "./interfaces/IFeesLogic.sol";
import "./Pool.sol";

import {console} from "forge-std/Test.sol";

/**
 * @dev TO DO
 * 
 * 1. check accuracy
 * 2. ensure pUnits and Epochs types are consistent
 */


contract FeesLogic is IFeesLogic/**, ReentrancyGuard*/ {
    // using LPDeclaration for LPDeclaration.Declaration;
    Pool public poolContract;

    /**
     * @dev poolLpDeclarations pool address to LP address to LPDeclaration structs.
     * @dev poolEpochFees pool address to array of epoch fees.
     * @dev poolEpochCounter returns the epoch value for a pool.
     * @dev poolEpochPDepth pool address to epoch to pDepth.
     * @dev instaBotFees pool to bot address to fees accumulated during the execution of streams.
     * @dev pools array of pool addresses.
     * @dev POOL_ADDRESS address of the pool contract.
     * @dev POOL_LOGIC_ADDRESS address of the pool logic contract.
     * 
     * @dev all storage should be migrated to the Pool contract
     */

    /** 
     * @dev mappings for the LP Declaration
    */
    mapping(address => mapping(address => uint32[])) public poolLpEpochs;
    mapping(address => mapping(address => uint32[])) public poolLpPUnits;
    /** */

    // mapping(address => mapping(address => LPDeclaration.Declaration)) public poolLpDeclarations;
    mapping(address => mapping(uint32 => uint256)) public poolEpochCounterFees;
    mapping(address => mapping(uint32 => uint256)) public poolEpochCounterFeesHistory;

    mapping(address => uint32) public poolEpochCounter;
    mapping(address => mapping(uint32 => uint32)) public poolEpochPDepth;
    mapping(address => mapping(address => uint256)) public instaBotFees;
    address[] public pools;

    address public override POOL_ADDRESS;
    address public override POOL_LOGIC_ADDRESS;
    uint256 public override BOT_FEE_BPS = 5;
    uint256 public override LP_FEE_BPS = 15;
    uint256 public override GLOBAL_FEE_PERCENTAGE = 45;
    uint256 public override POOL_LP_FEE_PERCENTAGE = 45;
    uint256 public override DECA_FEE_PERCENTAGE = 10;
    address public override DECA_ADDRESS;
    address public override REWARD_TOKEN_ADDRESS;

    constructor (address _poolAddress, address _poolLogicAddress) {
        POOL_ADDRESS = _poolAddress;
        POOL_LOGIC_ADDRESS = _poolLogicAddress;
    }

    //////////////////////////////////////////////////////////////////////////////////////////////
    ///////////////////////////////////////////////
    // PROXY FUNCTIONALITIES
    // ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
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
        poolEpochCounterFees[pool][epoch] += lpAmountToDebit; /**((amount * 15 >> 17) / 10000 << 17); //take 20BPS on the amountOut calculation*/
        uint256 botAmountToDebit = (amount * 5) / 10000;
        instaBotFees[pool][msg.sender] += botAmountToDebit; //take 5BPS on the amountIn calculation
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
        // _claimAccumulatedBotFees(pool);
        return amount - amountToDebit; //auto truncation in division operation means amoun returned is always as underestimate, and lp's benefit from the dust remaining
    }

    //////////////////////////////////////////////////////////////////////////////////////////////
    ///////////////////////////////////////////////
    // LP DECLARATION FUNCTIONALITIES
    // ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
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

    function _createLpDeclaration(address _liquidityProvider, address _pool, uint32 _pUnits) internal {
        uint32 currentEpoch = poolEpochCounter[_pool];
        // lets instead just populate the mappings for the two values of interest
        // poolEpochPDepth[_pool][currentEpoch] += _pUnits;
        poolLpEpochs[_pool][_liquidityProvider].push(currentEpoch);
        poolLpPUnits[_pool][_liquidityProvider].push(_pUnits);
        emit LpDeclarationCreated(_liquidityProvider);
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
        }
    }

    // /**
    //  * @dev closeLpDeclaration to be executed on on removal of all liquidity.
    //  *          note the withdraw functionality claimAllocation is automatically called at the end of function flow,
    //  *          ensuring that the LP is paid out for the last epoch they had liquidity in. As such, remove liquidity should 
    //  *          be called before add liquidity.
    //  *          note this function should only be called on the last stream execution of
    //  *          remove liquidity. 
    //  * @param _pool pool where declaration exists
    //  * @param _liquidityProvider LPs Eth address
    //  * 
    //  */
    // function closeLpDeclaration(address _pool, address _liquidityProvider) external {
    //     _closeLpDeclaration(_pool, _liquidityProvider);
    // }
    // function _closeLpDeclaration(address _pool, address _liquidityProvider) internal {
    //     // we withdraw fees for this last epoch
    //     claimLPAllocation(_pool, _liquidityProvider);
    //     // and then we close the declaration by pushiing a 0 into the end of the array
    //     poolLpEpochs[_pool][_liquidityProvider].push(0);
    // }
    ///////////////////////////////////////////////
    //////////////////////////////////////////////////////////////////////////////////////////////

    //////////////////////////////////////////////////////////////////////////////////////////////
    ///////////////////////////////////////////////
    // FEE DEBIT FUNCTIONALITIES
    // ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
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
    function _debitLpFeesFromSwapStream(address _pool, uint256 _feeInA) internal {
        uint32 epoch = poolEpochCounter[_pool];
        uint256 accumulatedFee = poolEpochCounterFees[_pool][epoch];
        accumulatedFee += _feeInA;
        poolEpochCounterFees[_pool][epoch] = accumulatedFee;
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
    function _debitBotFeesFromSwapStream(address _pool, uint256 _fee) internal {
        instaBotFees[_pool][msg.sender] += _fee;
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
    //     console.log("Debiting bot fees from liquidity stream ", _amount);
    //     uint256 existingAccumulation = instaBotFees[_pool][msg.sender];
    //     console.log("Existing accumulation: ", existingAccumulation);
    //     instaBotFees[_pool][msg.sender] += _amount;
    //     uint256 newAccumulation = instaBotFees[_pool][msg.sender];
    //     console.log("New accumulation: ", newAccumulation);
    //     console.log("bot fees after this debit are", instaBotFees[_pool][msg.sender]);
    // }

    /**
     * @dev transferAccumulatedFees 
     *          should be called at the end of each remove, add, or swap stream execution loop in bot logic,
     *          transferring the accumulated fees in each instance to the bot
     * @param _pool the address of the pool we transfer the fees from
     */
    function transferAccumulatedFees(address _pool) external 
    returns (uint256 fee)
    {
        require(msg.sender != address(0), "Invalid caller");
        fee = instaBotFees[_pool][msg.sender];
        require (fee > 0, "No fees available");
        // the following should only be executed at the completion of each flow
        // instaBotFees[_pool][msg.sender] = 0;
        // IPoolActions(POOL_ADDRESS).transferTokens(_pool, msg.sender, fee);
    }

    /**
     * @dev _endEpoch
     *          should be called on the iniialisation of each add/remove liquidity bot logic run
     * @param _pool the address of the pool whose epoch is being incremented
     */
    function _endEpoch(address _pool) internal {
        uint32 existingEpoch = poolEpochCounter[_pool];
        poolEpochCounter[_pool]++;
        uint256 feesAccumulated = poolEpochCounterFees[_pool][existingEpoch];
        poolEpochCounterFeesHistory[_pool][existingEpoch] = feesAccumulated;
        uint32 oldPDepth = poolEpochPDepth[_pool][existingEpoch];
        poolEpochPDepth[_pool][existingEpoch + 1] = oldPDepth;
    }
    ///////////////////////////////////////////////
    //////////////////////////////////////////////////////////////////////////////////////////////

    ///////////////////////////////////////////////
    //////////////////////////////////////////////////////////////////////////////////////////////
    // CLAIMING FUNCTIONALITIES

    /**
     * @dev claimAccumulatedBotFees 
     *          called by the bot to claim their fees. 
     *          the function iterates over the spread of epochs in the bot's declaration
     *          and calculates the allocation of fees for each epoch by taking the fractional
     *          allocation according to the pDepth. At the end of the iteration, the values
     *          are deleted from storage, and the sum is transferred instantly to the bot
     *          in the tokens they have executed streams for
     * 
     *          N.B. to be called once at the end of each streaming multithreaded loop,
     *          in each addLiquidity, removeLiquidity, and swap stream execution
     * @param _pool the token from which the bot has executed streams   
     */
    // function _claimAccumulatedBotFees(address _pool) internal /**onlyRouter*/ {
    //     uint256 fee = instaBotFees[_pool][msg.sender];
    //     require(fee > 0, "No fees available");
    //     instaBotFees[_pool][msg.sender] = 0;
    //     // IPoolActions(POOL_ADDRESS).transferTokens(_pool, msg.sender, fee);
    // }

    /**
     * @dev claimLPAllocation 
     *          called by an LP to claim their allocation of fees. 
     *          the function iterates over the spread of epochs in the LP's declaration
     *          and calculates the allocation of fees for each epoch by taking the fractional
     *          allocation according to the pDepth. At the end of the iteration, the values
     *          are deleted from storage, the currentEpoch value and corresponding pUnits
     *          held by the LP are cached, and the sum is transferred instantly to the LP
     *          in the tokens they have provided liquidity for.
     * @param pool the address of the pool where the LP has liquidity
     */

    function claimLPAllocation(address pool, address liquidityProvider) external override payable returns (uint256) {
        // @audit this needs to be built to find which kind of provider the calle is, and return the according portion
        uint256 allocation = _consumeLPAllocation(pool, liquidityProvider);
        return allocation;
        // IPoolActions(POOL_ADDRESS).transferTokens(pool, liquidityProvider, allocation);
    }

    function _consumeLPAllocation(address pool, address liquidityProvider) internal returns (uint256 allocation) {
        // LPDeclaration.Declaration storage provider = poolLpDeclarations[pool][msg.sender];

        uint32 currentEpoch = poolEpochCounter[pool];
        uint32[] memory lpEpochs = poolLpEpochs[pool][liquidityProvider];/**provider.lastClaimedEpoch;*/
        uint32[] memory lpPUnits = poolLpPUnits[pool][liquidityProvider];
        uint256 accumulator;

        if (lpPUnits.length == 0 || lpPUnits[lpPUnits.length - 1] == 0) revert InternalError();

        require(lpEpochs[lpEpochs.length - 1] != 0, "No declaration exists");
        require(lpEpochs[0] <= currentEpoch, "Invalid Epoch");
        require(lpEpochs[0] != currentEpoch, "LP's can only process completed epochs");
        
        if (lpEpochs[0] > currentEpoch) {
            revert InternalError();
            // this shouldn't be possible
        }
        allocation = _doctorBob(pool, liquidityProvider);
        console.log("returned an allocation of ", allocation);
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

    // function _algo(address pool, address lp) internal returns (uint256) {
    //     console.log("successfully called the 4th fee algo!");
    //     uint32[] memory lpEpochs = poolLpEpochs[pool][lp];/**provider.lastClaimedEpoch;*/
    //     uint32[] memory lpPUnits = poolLpPUnits[pool][lp];
    //     uint32 currentEpoch = poolEpochCounter[pool];
    //     console.log("executing fee claim for an lp up to epoch ", currentEpoch);
    //     // lets log out lpEpochs
    //     console.log("lpEpochs is 0 ", lpEpochs[0]);
    //     console.log("lpEpochs is 1 ", lpEpochs[1]);
    //     console.log("lpEpochs is 2 ", lpEpochs[2]);
    //     // and now we log out lpPUnits
    //     console.log("lpPUnits is 0 ", lpPUnits[0]);
    //     console.log("lpPUnits is 1 ", lpPUnits[1]);
    //     console.log("lpPUnits is 2 ", lpPUnits[2]);

    //     uint32 lastIteratedEpoch;
    //     uint256 accumulator;
    //     uint32 numberOfEpochsToIterate = currentEpoch - lpEpochs[0];

    //     for (uint32 index = 0; index < numberOfEpochsToIterate; index++) {
    //         console.log("in the loop! epoch is ", lpEpochs[index]);
    //         console.log("in loop number ", index);
    //         uint256 result = lpEpochs[index + 1] - lpEpochs[index];
    //         console.log("evaluator is ", result);
    //         if (lastIteratedEpoch + 1 == currentEpoch) {
    //             break;
    //         }
    //         if (lpEpochs[index + 1] - lpEpochs[index] != 1) {
    //             for (uint32 i = lpEpochs[index]; i < lpEpochs[index + 1]; i++) {
    //                 console.log("   epoch iterated in $A loop is ", i);
    //                 lastIteratedEpoch = i;
    //                 console.log("   making last iterated epoch,   ", lastIteratedEpoch);
    //                 uint256 fee = poolEpochCounterFeesHistory[pool][i];
    //                 uint256 pDepth = poolEpochPDepth[pool][i];
    //                 uint256 pUnits = lpPUnits[index];
    //                 accumulator += (fee * pUnits) / pDepth;
    //                 console.log("   accumulator in this epoch is ", accumulator);
    //             }
    //         } else {      
    //         console.log("reached $B loop");              
    //         uint32 epoch = lpEpochs[index];
    //         console.log("       epoch iterated in $B loop is ", epoch);
    //         lastIteratedEpoch = epoch;
    //         console.log("       equals last iterated epoch,   ", lastIteratedEpoch);
    //         uint256 pUnits = lpPUnits[index];
    //         console.log("       pUnits iterated in b loop is ", pUnits);
    //         uint256 feeAccruedInEpoch = poolEpochCounterFeesHistory[pool][epoch];
    //         console.log("       feeAccruedInEpoch iterated in b loop is ", feeAccruedInEpoch);
    //         uint256 pDepth = poolEpochPDepth[pool][epoch];
    //         console.log("       pDepth iterated in b loop is ", pDepth);
    //         accumulator += (feeAccruedInEpoch * pUnits) / pDepth;
    //         console.log("       accumulator iterated in b loop is ", accumulator);
    //         }
                  
    //     }
    //     uint256 ratio = _resolveTypeOfClaimant(lp, pool);
    //     // @audit need to handle precision here
    //     return accumulator * ratio / 100;
    // }

    /**
     * @dev _doctorBob
     *          the result of streaming epoch based rewards,
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
     */
    function _doctorBob(address pool, address lp) internal returns (uint256) {
        // lp specific information
        uint32[] memory lpEpochs = poolLpEpochs[pool][lp];
        uint32[] memory lpPUnits = poolLpPUnits[pool][lp];

        // sc specific information
        uint32 currentEpoch = poolEpochCounter[pool];
        uint256 phases = lpEpochs.length;

        // algo specific information
        uint256 lastIteratedIndex = 0;
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
                // poolEpochCounterFeesHistory[pool][epoch] -= accumulator; @audit we don't do this as running percentage claims are needed
            } else {
                feeInEpoch = poolEpochCounterFeesHistory[pool][epoch];
                pDepthInEpoch = poolEpochPDepth[pool][epoch];
                accumulator += (feeInEpoch * lastPUnits) / pDepthInEpoch;
                // poolEpochCounterFeesHistory[pool][epoch] -= accumulator;
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
        // we close the declaration by pushiing a 0 into the end of the array
        delete poolLpEpochs[_pool][_liquidityProvider];
        poolLpEpochs[_pool][_liquidityProvider].push(currentEpoch);
        delete poolLpPUnits[_pool][_liquidityProvider];
        poolLpPUnits[_pool][_liquidityProvider].push(lastPUnits);
    }

    ///////////////////////////////////////////////
    //////////////////////////////////////////////////////////////////////////////////////////////

    //////////////////////////////////////////////////////////////////////////////////////////////
    ///////////////////////////////////////////////
    // STATE FUNCTIONALITIES
    
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

    ///////////////////////////////////////////////
    //////////////////////////////////////////////////////////////////////////////////////////////

    //////////////////////////////////////////////////////////////////////////////////////////////
    ///////////////////////////////////////////////
    // LOGIC FUNCTIONALITIES

    function _resolveTypeOfClaimant(address pool, address claimant) internal returns (uint256) {
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

    ///////////////////////////////////////////////
    //////////////////////////////////////////////////////////////////////////////////////////////



}
