// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

contract Project {
    struct Market {
        uint256 id;
        string question;
        uint256 endTime;
        bool resolved;
        bool outcome;
        uint256 totalYesStake;
        uint256 totalNoStake;
        address creator;
    }

    struct Prediction {
        bool choice; // true for YES, false for NO
        uint256 amount;
        bool claimed;
    }

    mapping(uint256 => Market) public markets;
    mapping(uint256 => mapping(address => Prediction)) public predictions;
    
    uint256 public nextMarketId;
    uint256 public constant MARKET_DURATION = 7 days;
    uint256 public constant MIN_STAKE = 0.01 ether;
    
    event MarketCreated(uint256 indexed marketId, string question, uint256 endTime);
    event PredictionPlaced(uint256 indexed marketId, address indexed user, bool choice, uint256 amount);
    event MarketResolved(uint256 indexed marketId, bool outcome);
    event RewardClaimed(uint256 indexed marketId, address indexed user, uint256 amount);

    modifier marketExists(uint256 _marketId) {
        require(_marketId < nextMarketId, "Market does not exist");
        _;
    }

    modifier marketActive(uint256 _marketId) {
        require(block.timestamp < markets[_marketId].endTime, "Market has ended");
        require(!markets[_marketId].resolved, "Market already resolved");
        _;
    }

    modifier onlyCreator(uint256 _marketId) {
        require(msg.sender == markets[_marketId].creator, "Only creator can resolve");
        _;
    }

    /**
     * @dev Creates a new prediction market
     * @param _question The question or event to predict
     */
    function createMarket(string memory _question) external {
        uint256 marketId = nextMarketId++;
        
        markets[marketId] = Market({
            id: marketId,
            question: _question,
            endTime: block.timestamp + MARKET_DURATION,
            resolved: false,
            outcome: false,
            totalYesStake: 0,
            totalNoStake: 0,
            creator: msg.sender
        });

        emit MarketCreated(marketId, _question, markets[marketId].endTime);
    }

    /**
     * @dev Places a prediction on a market
     * @param _marketId ID of the market to predict on
     * @param _choice true for YES, false for NO
     */
    function placePrediction(uint256 _marketId, bool _choice) 
        external 
        payable 
        marketExists(_marketId)
        marketActive(_marketId)
    {
        require(msg.value >= MIN_STAKE, "Minimum stake not met");
        require(predictions[_marketId][msg.sender].amount == 0, "Already predicted on this market");

        predictions[_marketId][msg.sender] = Prediction({
            choice: _choice,
            amount: msg.value,
            claimed: false
        });

        if (_choice) {
            markets[_marketId].totalYesStake += msg.value;
        } else {
            markets[_marketId].totalNoStake += msg.value;
        }

        emit PredictionPlaced(_marketId, msg.sender, _choice, msg.value);
    }

    /**
     * @dev Resolves a market with the final outcome
     * @param _marketId ID of the market to resolve
     * @param _outcome true if YES won, false if NO won
     */
    function resolveMarket(uint256 _marketId, bool _outcome) 
        external 
        marketExists(_marketId)
        onlyCreator(_marketId)
    {
        require(block.timestamp >= markets[_marketId].endTime, "Market still active");
        require(!markets[_marketId].resolved, "Market already resolved");

        markets[_marketId].resolved = true;
        markets[_marketId].outcome = _outcome;

        emit MarketResolved(_marketId, _outcome);
    }

    /**
     * @dev Claims rewards for winning predictions
     * @param _marketId ID of the market to claim from
     */
    function claimReward(uint256 _marketId) 
        external 
        marketExists(_marketId)
    {
        require(markets[_marketId].resolved, "Market not resolved yet");
        
        Prediction storage userPrediction = predictions[_marketId][msg.sender];
        require(userPrediction.amount > 0, "No prediction found");
        require(!userPrediction.claimed, "Reward already claimed");
        require(userPrediction.choice == markets[_marketId].outcome, "Prediction was incorrect");

        Market storage market = markets[_marketId];
        uint256 winningPool = market.outcome ? market.totalYesStake : market.totalNoStake;
        uint256 losingPool = market.outcome ? market.totalNoStake : market.totalYesStake;
        
        require(winningPool > 0, "No winning pool");

        // Calculate reward: user's stake + proportional share of losing pool
        uint256 reward = userPrediction.amount + (userPrediction.amount * losingPool / winningPool);
        
        userPrediction.claimed = true;
        
        (bool success, ) = payable(msg.sender).call{value: reward}("");
        require(success, "Transfer failed");

        emit RewardClaimed(_marketId, msg.sender, reward);
    }

    // View functions
    function getMarket(uint256 _marketId) external view returns (Market memory) {
        return markets[_marketId];
    }

    function getUserPrediction(uint256 _marketId, address _user) external view returns (Prediction memory) {
        return predictions[_marketId][_user];
    }

    function getTotalMarkets() external view returns (uint256) {
        return nextMarketId;
    }
}
