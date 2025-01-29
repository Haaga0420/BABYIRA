solidity
// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

// Importing OpenZeppelin's contract libraries
import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/security/ReentrancyGuard.sol";
import "@openzeppelin/contracts/utils/math/SafeMath.sol";
import "@openzeppelin/contracts/access/AccessControl.sol";
import "@openzeppelin/contracts/security/Pausable.sol";

interface IRewardToken {
    function transfer(address recipient, uint256 amount) external returns (bool);
    function balanceOf(address account) external view returns (uint256);
}

interface IUniswapRouter {
    function swapExactETHForTokens(
        uint256 amountOutMin,
        address[] calldata path,
        address to,
        uint256 deadline
    ) external payable returns (uint256[] memory amounts);
}

// BabyIRA contract inherits from OpenZeppelin's Ownable, ReentrancyGuard, AccessControl, and Pausable contracts
contract BabyIRA is Ownable, ReentrancyGuard, AccessControl, Pausable {
    using SafeMath for uint256;  // Using SafeMath for safe arithmetic operations

    string public name = "BabyIRA";
    string public symbol = "TiTbaby";
    uint256 public totalSupply = 420024069960 * 10**18;  // total supply with decimals
    uint256 public sellTaxPercentage = 25;  // Initial sell tax
    uint256 public constant defaultSellTax = 5;  // Default sell tax after initial phase
    uint256 public constant defaultBuyTax = 5;  // Default buy tax
    uint256 public rewardToken1TaxBuy = 2;  // Default tax for reward token 1 on buys
    uint256 public rewardToken1TaxSell = 2;  // Default tax for reward token 1 on sells
    uint256 public rewardToken2TaxBuy = 2;  // Default tax for reward token 2 on buys
    uint256 public rewardToken2TaxSell = 2;  // Default tax for reward token 2 on sells

    address public giveawayWallet = 0x52E2Bc2fef771142aEbAe4F46931a8b71652a346;
    address public marketingWallet = 0xd6c7845d4bfca757C9C9eB3eFDA0F888fF8268f0;
    address public rewardToken1 = 0x029C58A909fBe3d4BE85a24f414DDa923A3Fde0F;
    address public rewardToken2 = 0xEeeeeEeeeEeEeeEeEeEeeEEEeeeeEeeeeeeeEEeE;

    IUniswapRouter public uniswapRouter;

    mapping(address => uint256) public balances;
    mapping(address => mapping(address => uint256)) public allowance;
    mapping(address => bool) public isHolder;  // Track if an address is a holder
    address[] public holders;  // Array of holders

    uint256 public launchBlock;
    bool public paused = false;  // For reward distribution

    uint256 public collectedFees;
    uint256 public lastRewardDistributionTime;
    uint256 public constant DISTRIBUTION_INTERVAL = 3 hours;  // Track rewards for holders

    mapping(address => uint256) public claimedRewards;  // Track claimed rewards
    uint256 public totalRewardAllocations;  // Total rewards allocated to holders

    event Transfer(address indexed from, address indexed to, uint256 value);
    event Approval(
        address indexed owner,
        address indexed spender,
        uint256 value
    );
    event TaxUpdated(uint256 newSellTax, uint256 newBuyTax);
    event RewardTokenTaxUpdated(
        uint256 rewardToken1BuyTax,
        uint256 rewardToken1SellTax,
        uint256 rewardToken2BuyTax,
        uint256 rewardToken2SellTax
    );
    event Paused();
    event Unpaused();
    event RewardsDistributed(uint256 amountRewarded);
    event WithdrawnToGiveawayWallet(uint256 amount);
    event TokensPurchasedWithFees(
        uint256 amountSpent,
        uint256 rewardToken1Amount,
        uint256 rewardToken2Amount
    );

    // Function modifiers
    modifier onlyOwner() {
        require(owner() == _msgSender(), "Not the contract owner");
        _;
    }
    modifier whenNotPaused() {
        require(!paused, "Contract is paused");
        _;
    }

    constructor(address _uniswapRouter) {
        uniswapRouter = IUniswapRouter(_uniswapRouter);
        isHolder[owner()] = true;  // Mark owner as holder
        holders.push(owner());  // Add owner to holders list
        _mint(owner(), totalSupply);  // Mint total supply to contract owner
        launchBlock = block.number;  // Set the launch block
        lastRewardDistributionTime = block.timestamp;  // Initialize last distribution time
    }

    // Track rewards for holders
    mapping(address => uint256) public claimedRewards; // Track claimed rewards
    uint256 public totalRewardAllocations; // Total rewards allocated to holders

    event Transfer(address indexed from, address indexed to, uint256 value);
    event Approval(
        address indexed owner,
        address indexed spender,
        uint256 value
    );
    event TaxUpdated(uint256 newSellTax, uint256 newBuyTax);
    event RewardTokenTaxUpdated(
        uint256 rewardToken1BuyTax,
        uint256 rewardToken1SellTax,
        uint256 rewardToken2BuyTax,
        uint256 rewardToken2SellTax
    );
    event Paused();
    event Unpaused();
    event RewardsDistributed(uint256 amountRewarded);
    event WithdrawnToGiveawayWallet(uint256 amount);
    event TokensPurchasedWithFees(
        uint256 amountSpent,
        uint256 rewardToken1Amount,
        uint256 rewardToken2Amount
    );

    modifier onlyOwner() {
        require(msg.sender == owner, "Not the contract owner");
        _;
    }

    modifier whenNotPaused() {
        require(!paused, "Contract is paused");
        _;
    }

    constructor(address _uniswapRouter) {
        owner = msg.sender;
        balances[owner] = totalSupply; // Assign total supply to contract owner
        launchBlock = block.number; // Set the launch block
        lastRewardDistributionTime = block.timestamp; // Initialize last distribution time
        uniswapRouter = IUniswapRouter(_uniswapRouter);
        isHolder[owner] = true; // Mark owner as holder
        holders.push(owner); // Add owner to holders list
    }

    function transfer(address recipient, uint256 amount)
        public
        whenNotPaused
        returns (bool)
    {
        require(balances[msg.sender] >= amount, "Insufficient balance");

        uint256 fee = (amount * 1) / 1000; // 0.1% fee
        uint256 taxAmount = calculateTax(amount);
        uint256 amountAfterTax = amount - taxAmount - fee;

        balances[msg.sender] -= amount;
        balances[recipient] += amountAfterTax;

        // Update collected fees
        collectedFees += fee;

        // Update holder tracking
        updateHolderStatus(recipient);

        // Distribute tax
        distributeTax(taxAmount);

        emit Transfer(msg.sender, recipient, amountAfterTax);
        return true;
    }

    function updateHolderStatus(address holder) internal {
        if (!isHolder[holder]) {
            isHolder[holder] = true;
            holders.push(holder);
        }
    }

    function calculateTax(uint256 _amount) internal view returns (uint256) {
        uint256 taxRate = (blocksSinceLaunch() < 4)
            ? sellTaxPercentage
            : defaultSellTax;
        return (_amount * taxRate) / 100;
    }

    function distributeTax(uint256 taxAmount) internal {
        uint256 giveawayTax = taxAmount / 10; // Example: 10% of tax goes to giveaway
        uint256 marketingTax = taxAmount / 10; // Example: 10% of tax goes to marketing
        uint256 burnTax = taxAmount / 5; // Example: 20% of tax is burned

        // Send taxes to respective wallets
        payable(giveawayWallet).transfer(giveawayTax);
        payable(marketingWallet).transfer(marketingTax);

        // Burn the tokens by sending to zero address
        balances[address(0)] += burnTax;

        // Emit transfers for tax distribution
        emit Transfer(msg.sender, giveawayWallet, giveawayTax);
        emit Transfer(msg.sender, marketingWallet, marketingTax);
        emit Transfer(msg.sender, address(0), burnTax);
    }

    function recoverETH() external onlyOwner {
        payable(owner).transfer(address(this).balance);
    }

    function setSellTax(uint256 newTax) external onlyOwner {
        sellTaxPercentage = newTax;
        emit TaxUpdated(newTax, defaultBuyTax);
    }

    function setRewardTokenTaxes(
        uint256 _rewardToken1TaxBuy,
        uint256 _rewardToken1TaxSell,
        uint256 _rewardToken2TaxBuy,
        uint256 _rewardToken2TaxSell
    ) external onlyOwner {
        rewardToken1TaxBuy = _rewardToken1TaxBuy;
        rewardToken1TaxSell = _rewardToken1TaxSell;
        rewardToken2TaxBuy = _rewardToken2TaxBuy;
        rewardToken2TaxSell = _rewardToken2TaxSell;
        emit RewardTokenTaxUpdated(
            _rewardToken1TaxBuy,
            _rewardToken1TaxSell,
            _rewardToken2TaxBuy,
            _rewardToken2TaxSell
        );
    }

    function distributeRewards() external {
        require(
            block.timestamp >=
                lastRewardDistributionTime + DISTRIBUTION_INTERVAL,
            "Distribution not allowed yet"
        );
        lastRewardDistributionTime = block.timestamp;

        // Calculate total supply of BabyIRA for distribution calculation
        uint256 totalSupplyBabyIRA = totalSupply;
        require(
            totalSupplyBabyIRA > 0,
            "No BabyIRA tokens available for distribution"
        );

        // Swap collected fees for reward tokens
        purchaseRewardTokens();

        // Calculate rewards in proportion to the amount held
        uint256 rewardToken1Balance = IRewardToken(rewardToken1).balanceOf(
            address(this)
        );
        uint256 rewardToken2Balance = IRewardToken(rewardToken2).balanceOf(
            address(this)
        );
        totalRewardAllocations = rewardToken1Balance + rewardToken2Balance; // Track total rewards allocated

        emit RewardsDistributed(totalRewardAllocations);
    }

    function claimRewards() external {
        uint256 holderBalance = balances[msg.sender];
        require(holderBalance > 0, "No BabyIRA tokens held");

        uint256 rewardToken1Balance = IRewardToken(rewardToken1).balanceOf(
            address(this)
        );
        uint256 rewardToken2Balance = IRewardToken(rewardToken2).balanceOf(
            address(this)
        );

        uint256 holderReward1 = (rewardToken1Balance * holderBalance) /
            totalSupply;
        uint256 holderReward2 = (rewardToken2Balance * holderBalance) /
            totalSupply;

        // Transfer the reward tokens
        if (holderReward1 > 0) {
            IRewardToken(rewardToken1).transfer(msg.sender, holderReward1);
        }
        if (holderReward2 > 0) {
            IRewardToken(rewardToken2).transfer(msg.sender, holderReward2);
        }
    }

    function withdrawToGiveawayWallet(uint256 amount) external onlyOwner {
        require(amount <= collectedFees, "Insufficient fees collected");
        collectedFees -= amount;
        payable(giveawayWallet).transfer(amount);
        emit WithdrawnToGiveawayWallet(amount);
    }

    function purchaseRewardTokens() internal {
        require(collectedFees > 0, "No fees collected");
        uint256 amountToSpend = collectedFees;

        // Define the path for swapping: ETH -> Reward Token 1
        address[] memory path1 = new address[](2);
        path1[0] = address(0); // Using ETH
        path1[1] = rewardToken1; // Reward Token 1

        // Perform the swap on Uniswap for Reward Token 1
        uniswapRouter.swapExactETHForTokens{value: amountToSpend}(
            0,
            path1,
            address(this),
            block.timestamp + 600
        );

        // Define the path for swapping: ETH -> Reward Token 2
        address[] memory path2 = new address[](2);
        path2[0] = address(0); // Using ETH
        path2[1] = rewardToken2; // Reward Token 2

        // Perform the swap on Uniswap for Reward Token 2
        uniswapRouter.swapExactETHForTokens{value: amountToSpend}(
            0,
            path2,
            address(this),
            block.timestamp + 600
        );

        emit TokensPurchasedWithFees(amountToSpend, 0, 0); // Update with actual amounts
        collectedFees = 0; // Reset collected fees after purchasing
    }

    function pause() external onlyOwner {
        paused = true;
        emit Paused();
    }

    function unpause() external onlyOwner {
        paused = false;
        emit Unpaused();
    }

    function blocksSinceLaunch() public view returns (uint256) {
        return block.number - launchBlock; // Returns the number of blocks since contract was deployed
    }

    function approve(address spender, uint256 amount) public returns (bool) {
        allowance[msg.sender][spender] = amount;
        emit Approval(msg.sender, spender, amount);
        return true;
    }

    function transferFrom(
        address sender,
        address recipient,
        uint256 amount
    ) public returns (bool) {
        require(balances[sender] >= amount, "Insufficient balance");
        require(allowance[sender][msg.sender] >= amount, "Allowance exceeded");

        uint256 fee = (amount * 1) / 1000; // 0.1% fee
        uint256 taxAmount = calculateTax(amount);
        uint256 amountAfterTax = amount - taxAmount - fee;

        balances[sender] -= amount;
        balances[recipient] += amountAfterTax;
        allowance[sender][msg.sender] -= amount;

        // Update collected fees
        collectedFees += fee;

        // Distribute tax
        distributeTax(taxAmount);

        emit Transfer(sender, recipient, amountAfterTax);
        return true;
    }

    function balanceOf(address account) public view returns (uint256) {
        return balances[account];
    }
}

