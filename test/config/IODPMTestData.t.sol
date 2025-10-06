// SPDX-License-Identifier: UNLICENSED
pragma solidity >=0.8.28 <0.9.0;

// Test utils
import { GenerateTestShareDistributions } from "@test/utils/GenerateTestShareDistributions.sol";
// Config
import { IODPMTestConstants } from "@test/config/IODPMTestConstants.sol";

/**
 * @title IODPMTestData
 * @dev Generates test data for OnitInfiniteOutcomeDPM
 *
 * - Arrays of test predictions for each distribution type (normal, uniform, discrete)
 */
contract IODPMTestData is IODPMTestConstants {
    /**
     * @dev Some restrictions on betting values and domain to generate test values over
     */
    int256 internal constant DOMAIN_START = 0;
    int256 internal constant DOMAIN_END = 2_000_000;
    int256 internal constant DOMAIN_START_SCALED = DOMAIN_START * SCALE;
    int256 internal constant DOMAIN_END_SCALED = DOMAIN_END * SCALE;
    int256 internal constant MIN_MEAN = DOMAIN_START + MIN_STD_DEV;
    int256 internal constant MAX_MEAN = DOMAIN_END - MAX_STD_DEV;
    int256 internal constant MIN_MEAN_SCALED = MIN_MEAN * SCALE;
    int256 internal constant MAX_MEAN_SCALED = MAX_MEAN * SCALE;
    int256 internal constant MIN_STD_DEV = 10_000; // 10000/2000000 = 0.5% of the domain
    int256 internal constant MAX_STD_DEV = 100_000; // 50000/2000000 = 2.5% of the domain
    int256 internal constant MIN_STD_DEV_SCALED = MIN_STD_DEV * SCALE;
    int256 internal constant MAX_STD_DEV_SCALED = MAX_STD_DEV * SCALE;

    // Minimum number of options for discrete distributions
    uint256 internal constant MIN_DISCRETE_OPTIONS = 2;
    uint256 internal constant MAX_DISCRETE_OPTIONS = 10;

    /**
     * Test parameters
     */
    int256 internal constant INITIAL_MEAN = 100_000;
    int256 internal constant INITIAL_STD_DEV = 40_000;
    int256 internal constant SECOND_MEAN = 130_000;
    int256 internal constant SECOND_STD_DEV = 30_000;

    // Score of test values from the mean (0 = no score = all same, 1 ether = score over full range)
    int256 internal constant DISTRIBUTION_SPREAD = 1 ether;

    enum DistributionType {
        NORMAL,
        UNIFORM,
        DISCRETE
    }

    struct BaseTestConfig {
        uint256 numTests;
        uint256 minValue;
        uint256 maxValue;
        DistributionType distributionType;
    }

    struct NormalTestConfig {
        BaseTestConfig base;
        int256 minMean;
        int256 maxMean;
        int256 minStdDev;
        int256 maxStdDev;
    }

    struct UniformTestConfig {
        BaseTestConfig base;
        int256 minStart;
        int256 maxStart;
        int256 minEnd;
        int256 maxEnd;
    }

    struct DiscreteTestConfig {
        BaseTestConfig base;
        uint256 minOptions;
        uint256 maxOptions;
        int256 minOptionValue;
        int256 maxOptionValue;
    }

    // How related predictions are (0 = identical, 1 ether = score over full range)
    struct TestArrayDistributionConfig {
        int256 meanDev;
        int256 stdDevDev;
        // For uniform distribution
        int256 startDev;
        int256 endDev;
        // For discrete distribution
        int256 optionsDev;
    }

    struct TestPrediction {
        address predictor;
        uint256 predictorPk;
        uint256 value;
        DistributionType distributionType;
        // Normal distribution parameters
        int256 mean;
        int256 stdDev;
        // Uniform distribution parameters
        int256 start;
        int256 end;
        // Common outputs
        int256[] bucketIds;
        int256[] shares;
    }

    GenerateTestShareDistributions gen;

    constructor() {
        gen = new GenerateTestShareDistributions(OUTCOME_UNIT, BASE_SHARES);
    }

    function getDefaultBaseTestConfig() public pure returns (BaseTestConfig memory) {
        return BaseTestConfig({
            numTests: 2, minValue: MIN_BET_SIZE, maxValue: MAX_BET_SIZE, distributionType: DistributionType.NORMAL
        });
    }

    function getDefaultNormalTestConfig() public pure returns (NormalTestConfig memory) {
        return NormalTestConfig({
            base: getDefaultBaseTestConfig(),
            minMean: MIN_MEAN,
            maxMean: MAX_MEAN,
            minStdDev: MIN_STD_DEV,
            maxStdDev: MAX_STD_DEV
        });
    }

    function getDefaultUniformTestConfig() public pure returns (UniformTestConfig memory) {
        return UniformTestConfig({
            base: getDefaultBaseTestConfig(),
            minStart: MIN_MEAN, // Used for bounds checking
            maxStart: MAX_MEAN,
            minEnd: MIN_STD_DEV, // Not used for uniform
            maxEnd: MAX_STD_DEV
        });
    }

    function getDefaultDiscreteTestConfig() public pure returns (DiscreteTestConfig memory) {
        return DiscreteTestConfig({
            base: getDefaultBaseTestConfig(),
            minOptions: MIN_DISCRETE_OPTIONS,
            maxOptions: MAX_DISCRETE_OPTIONS,
            minOptionValue: MIN_MEAN, // Used as bounds for option values
            maxOptionValue: MAX_MEAN
        });
    }

    // 1 ether = 100% deviation, 0 = no deviation (all same)
    function getDefaultTestArrayDistributionConfig() public pure returns (TestArrayDistributionConfig memory) {
        return TestArrayDistributionConfig({
            meanDev: 1 ether, stdDevDev: 1 ether, startDev: 1 ether, endDev: 1 ether, optionsDev: 1 ether
        });
    }

    // @dev Temporary adapter function for backward compatibility
    function getDefaultTestConfig() public pure returns (NormalTestConfig memory) {
        return getDefaultNormalTestConfig();
    }

    function generateNormalDistributionPredictionArray(
        NormalTestConfig memory config,
        TestArrayDistributionConfig memory distributionConfig,
        uint256 seed
    )
        public
        returns (TestPrediction[] memory predictions)
    {
        return _generateNormalDistributionPredictionArray(config, distributionConfig, seed);
    }

    function generateNormalDistributionPredictionArray(NormalTestConfig memory config, uint256 seed)
        public
        returns (TestPrediction[] memory predictions)
    {
        return _generateNormalDistributionPredictionArray(config, getDefaultTestArrayDistributionConfig(), seed);
    }

    function generateUniformDistributionPredictionArray(
        UniformTestConfig memory config,
        TestArrayDistributionConfig memory distributionConfig,
        uint256 seed
    )
        public
        returns (TestPrediction[] memory predictions)
    {
        return _generateUniformDistributionPredictionArray(config, distributionConfig, seed);
    }

    function generateDiscreteDistributionPredictionArray(
        DiscreteTestConfig memory config,
        TestArrayDistributionConfig memory distributionConfig,
        uint256 seed
    )
        public
        returns (TestPrediction[] memory predictions)
    {
        return _generateDiscreteDistributionPredictionArray(config, distributionConfig, seed);
    }

    function _generateNormalDistributionPredictionArray(
        NormalTestConfig memory config,
        TestArrayDistributionConfig memory distributionConfig,
        uint256 seed
    )
        public
        returns (TestPrediction[] memory predictions)
    {
        predictions = new TestPrediction[](config.base.numTests);

        for (uint256 i = 0; i < config.base.numTests; i++) {
            uint256 predictionSeed = uint256(keccak256(abi.encode(seed, i)));
            (address predictor, uint256 predictorPk) = makeAddrAndKey(vm.toString(uint160(predictionSeed)));
            uint256 value = bound(
                uint256(keccak256(abi.encode(predictionSeed, "value"))), config.base.minValue, config.base.maxValue
            );

            vm.deal(predictor, 100 ether);

            // Initialize a prediction with empty arrays
            TestPrediction memory prediction = TestPrediction({
                predictor: predictor,
                predictorPk: predictorPk,
                value: value,
                distributionType: DistributionType.NORMAL,
                mean: 0,
                stdDev: 0,
                start: 0,
                end: 0,
                bucketIds: new int256[](0),
                shares: new int256[](0)
            });

            _generateNormalDistributionPrediction(prediction, config, distributionConfig, predictionSeed);

            predictions[i] = prediction;
        }

        return predictions;
    }

    function _generateUniformDistributionPredictionArray(
        UniformTestConfig memory config,
        TestArrayDistributionConfig memory distributionConfig,
        uint256 seed
    )
        public
        returns (TestPrediction[] memory predictions)
    {
        predictions = new TestPrediction[](config.base.numTests);

        for (uint256 i = 0; i < config.base.numTests; i++) {
            uint256 predictionSeed = uint256(keccak256(abi.encode(seed, i)));
            (address predictor, uint256 predictorPk) = makeAddrAndKey(vm.toString(uint160(predictionSeed)));
            uint256 value = bound(
                uint256(keccak256(abi.encode(predictionSeed, "value"))), config.base.minValue, config.base.maxValue
            );

            vm.deal(predictor, 100 ether);

            // Initialize a prediction with empty arrays
            TestPrediction memory prediction = TestPrediction({
                predictor: predictor,
                predictorPk: predictorPk,
                value: value,
                distributionType: DistributionType.UNIFORM,
                mean: 0,
                stdDev: 0,
                start: 0,
                end: 0,
                bucketIds: new int256[](0),
                shares: new int256[](0)
            });

            _generateUniformDistributionPrediction(prediction, config, distributionConfig, predictionSeed);

            predictions[i] = prediction;
        }

        return predictions;
    }

    function _generateDiscreteDistributionPredictionArray(
        DiscreteTestConfig memory config,
        TestArrayDistributionConfig memory distributionConfig,
        uint256 seed
    )
        public
        returns (TestPrediction[] memory predictions)
    {
        predictions = new TestPrediction[](config.base.numTests);

        for (uint256 i = 0; i < config.base.numTests; i++) {
            uint256 predictionSeed = uint256(keccak256(abi.encode(seed, i)));
            (address predictor, uint256 predictorPk) = makeAddrAndKey(vm.toString(uint160(predictionSeed)));
            uint256 value = bound(
                uint256(keccak256(abi.encode(predictionSeed, "value"))), config.base.minValue, config.base.maxValue
            );

            vm.deal(predictor, 100 ether);

            // Initialize a prediction with empty arrays
            TestPrediction memory prediction = TestPrediction({
                predictor: predictor,
                predictorPk: predictorPk,
                value: value,
                distributionType: DistributionType.DISCRETE,
                mean: 0,
                stdDev: 0,
                start: 0,
                end: 0,
                bucketIds: new int256[](0),
                shares: new int256[](0)
            });

            _generateDiscreteDistributionPrediction(prediction, config, distributionConfig, predictionSeed);

            predictions[i] = prediction;
        }

        return predictions;
    }

    function _generateNormalDistributionPrediction(
        TestPrediction memory prediction,
        NormalTestConfig memory config,
        TestArrayDistributionConfig memory distributionConfig,
        uint256 predictionSeed
    )
        internal
        view
    {
        int256 baseMean = int256((config.minMean + config.maxMean) / 2);
        int256 baseStdDev = int256((config.minStdDev + config.maxStdDev) / 2);

        // Calculate random deviations within the score-adjusted range
        int256 meanDevForTest = int256(
            bound(
                uint256(keccak256(abi.encode(predictionSeed, "meanDev"))),
                0,
                uint256(((baseMean) * distributionConfig.meanDev) / DISTRIBUTION_SPREAD)
            )
        );
        int256 stdDevDevForTest = int256(
            bound(
                uint256(keccak256(abi.encode(predictionSeed, "stdDevDev"))),
                0,
                uint256(((baseStdDev) * distributionConfig.stdDevDev) / DISTRIBUTION_SPREAD)
            )
        );

        int256 finalMean = (int256(
                bound(
                    // Direction +/- depending on the mod of meanDevForTest
                    uint256(baseMean + meanDevForTest * (meanDevForTest % 2 == 0 ? int256(1) : int256(-1))),
                    uint256(config.minMean),
                    uint256(config.maxMean)
                )
            ));

        // Calculate max stddev as 1/3 of mean (3-sigma rule)
        int256 maxStdDevForMean = finalMean / 3;
        int256 effectiveMaxStdDev = maxStdDevForMean < config.maxStdDev ? maxStdDevForMean : config.maxStdDev;
        // Ensure effective max is not less than MIN_STD_DEV_SCALED
        effectiveMaxStdDev = effectiveMaxStdDev > config.minStdDev ? effectiveMaxStdDev : config.minStdDev;

        // Ensure final std dev stays within bounds
        int256 finalStdDev = (int256(
                bound(
                    // Direction +/- depending on the mod of stdDevDevForTest
                    uint256(baseStdDev + stdDevDevForTest * (stdDevDevForTest % 2 == 0 ? int256(1) : int256(-1))),
                    uint256(config.minStdDev),
                    uint256(effectiveMaxStdDev)
                )
            ));

        (int256[] memory bucketIds, int256[] memory shares) =
            gen.generateNormalDistribution(finalMean, finalStdDev, OUTCOME_UNIT);

        prediction.mean = finalMean;
        prediction.stdDev = finalStdDev;
        prediction.bucketIds = bucketIds;
        prediction.shares = shares;
    }

    function _generateUniformDistributionPrediction(
        TestPrediction memory prediction,
        UniformTestConfig memory config,
        TestArrayDistributionConfig memory distributionConfig,
        uint256 predictionSeed
    )
        internal
        view
    {
        // For uniform distribution we need start and end points
        int256 domainMiddle = (DOMAIN_START + DOMAIN_END) / 2;
        int256 maxRange = (DOMAIN_END - DOMAIN_START) / 2; // Half the total domain

        // Calculate random deviations for start and end
        int256 startDevForTest = int256(
            bound(
                uint256(keccak256(abi.encode(predictionSeed, "startDev"))),
                0,
                uint256((maxRange * distributionConfig.startDev) / DISTRIBUTION_SPREAD)
            )
        );
        int256 endDevForTest = int256(
            bound(
                uint256(keccak256(abi.encode(predictionSeed, "endDev"))),
                0,
                uint256((maxRange * distributionConfig.endDev) / DISTRIBUTION_SPREAD)
            )
        );

        // Generate a random range that's at least 10% of the domain to ensure meaningful distributions
        int256 minRangeSize = (DOMAIN_END - DOMAIN_START) / 10;

        // Generate start point
        int256 start = int256(
            bound(
                // Direction +/- depending on the mod
                uint256(domainMiddle - startDevForTest * (startDevForTest % 2 == 0 ? int256(1) : int256(-1))),
                uint256(config.minStart),
                uint256(config.maxStart)
            )
        );

        // Generate end point (ensuring it's greater than start + minRangeSize)
        int256 end = int256(
            bound(
                uint256(domainMiddle + endDevForTest * (endDevForTest % 2 == 0 ? int256(1) : int256(-1))),
                uint256(start + minRangeSize),
                uint256(config.maxEnd)
            )
        );

        // Generate bucket IDs and shares for uniform distribution
        (int256[] memory bucketIds, int256[] memory shares) = gen.generateUniformDistribution(start, end, OUTCOME_UNIT);

        prediction.start = start;
        prediction.end = end;
        prediction.bucketIds = bucketIds;
        prediction.shares = shares;
    }

    function _generateDiscreteDistributionPrediction(
        TestPrediction memory prediction,
        DiscreteTestConfig memory config,
        TestArrayDistributionConfig memory, // distribution config not currently used in these tests
        uint256 predictionSeed
    )
        internal
        view
    {
        // Determine number of options (between MIN_DISCRETE_OPTIONS and MAX_DISCRETE_OPTIONS)
        uint256 numOptions =
            bound(uint256(keccak256(abi.encode(predictionSeed, "numOptions"))), config.minOptions, config.maxOptions);

        int256[] memory options = new int256[](numOptions);
        int256[] memory amounts = new int256[](numOptions);

        // Generate random options within the domain
        for (uint256 i = 0; i < numOptions; i++) {
            options[i] = int256(
                bound(
                    uint256(keccak256(abi.encode(predictionSeed, "option", i))),
                    uint256(config.minOptionValue),
                    uint256(config.maxOptionValue)
                )
            );

            // Ensure options are ordered
            if (i > 0 && options[i] <= options[i - 1]) {
                options[i] = options[i - 1] + 1;
            }

            // Generate a random amount for each option
            amounts[i] = int256(
                bound(
                    uint256(keccak256(abi.encode(predictionSeed, "amount", i))),
                    1, // Minimum of 1 to avoid zeros
                    100 // Some arbitrary maximum
                )
            );
        }

        // Generate bucket IDs and shares for discrete distribution
        (int256[] memory bucketIds, int256[] memory shares) = gen.generateDiscreteDistribution(options, amounts);

        prediction.bucketIds = bucketIds;
        prediction.shares = shares;
    }
}
