// SPDX-License-Identifier: MIT
pragma solidity ^0.8.2;

import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "@openzeppelin/contracts/token/ERC20/extensions/ERC20Burnable.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/token/ERC20/extensions/draft-ERC20Permit.sol";
import "@openzeppelin/contracts/token/ERC20/extensions/ERC20Votes.sol";
import './AccountFrozenBalances.sol';
import "./Rules.sol";
import "./IERC20Token.sol";

contract ELGTToken is AccountFrozenBalances, ERC20, ERC20Burnable, Ownable, ERC20Permit, ERC20Votes {

    using SafeMath for uint256;
    using Rules for Rules.Rule;

    uint256 constant public maxCallFrequency = 100;
    uint256 public totalSupplyLimit;

    // 游戏奖励、生态奖励、基金会、流动性、合作顾问、PreSale PublicSale
    enum RoleType { INVALID, GAME, COMMUNITY, FUNDER_AIRPORT, FUNDER, ACTIVE, ADVISORS, PRESALE, PRIVATESALE, PUBLICSALE }

    struct FreezeData {
        bool initialzed;
        uint256 frozenAmount;       // fronzen amount
        uint256 startBlock;         // freeze block for start.
        uint256 lastFreezeBlock;
    }

    struct Unusual {
        uint256 releaseBn;
        uint256 releaseAmount;
        bool    released;
    }

    mapping (address => RoleType) private _roles;
    mapping (uint256 => Rules.Rule) private _rules;
    mapping (address => FreezeData) private _freeze_datas;
    mapping (address => Unusual) private _unusual;
    uint256 public monthIntervalBlock = 172800;    // 172800 (30d*24h*60m*60s/15s)
    uint256 public yearIntervalBlock = 2102400;    // 2102400 (365d*24h*60m*60s/15s)
    uint256 public sixMonthIntervalBlock = 1036800; // six month block: 1036800 (6m*30d*24h*60m*60s/15s)

    bool public seedPause = true;
    uint256 public seedMeltStartBlock = 0;       
    bool public ruleReady;

    // upgrade part
    uint256 private _totalUpgraded;    

    modifier onlyReady(){
        require(ruleReady, "ruleReady is false");
        _;
    }            

    modifier canClaim() {
        require(uint256(_roles[msg.sender]) != uint256(RoleType.INVALID), "Invalid user role");
        require(_freeze_datas[msg.sender].initialzed);
        /*if(_roles[msg.sender] == RoleType.SEED){
            require(!seedPause, "Seed is not time to unlock yet");
        }*/
        _;
    }

    modifier canMint(uint256 _amount) {
        require((totalSupply() + _amount) <= totalSupplyLimit, "Mint: Exceed the maximum circulation");
        _;
    }

    modifier roleCanMint(uint256 _role, uint256 _amount) {
        require(_rules[_role].initRule, "role not exists or not initialzed");
        require(_amount <= _rules[_role].remainAmount, "RoleMint: Exceed the maximum circulation");
        _;
        _rules[_role].remainAmount = _rules[_role].remainAmount.sub(_amount);
    }

    modifier canBatchMint(uint256[] memory _amounts) {
        uint256 mintAmount = 0;
        for (uint256 i = 0; i < _amounts.length; i++) {
            mintAmount = mintAmount.add(_amounts[i]);
        }
        require((totalSupply() + mintAmount) <= totalSupplyLimit, "BatchMint: Exceed the maximum circulation");
        _;
    }

    modifier roleCanBatchMint(uint256 _role, uint256[] memory _amounts) {
        uint256 mintAmount = 0;
        for (uint256 i = 0; i < _amounts.length; i++) {
            mintAmount = mintAmount.add(_amounts[i]);
        }
        require(mintAmount <= _rules[_role].remainAmount, "RoleBatchMint: Exceed the maximum circulation");
        _;
        _rules[_role].remainAmount = _rules[_role].remainAmount.sub(mintAmount);
    }

    event Freeze(address indexed from, uint256 amount);
    event Melt(address indexed from, uint256 amount);
    event MintFrozen(address indexed to, uint256 amount);
    event Claim(address indexed from, uint256 amount);

    event Withdrawal(address indexed src, uint wad);
    event FrozenTransfer(address indexed from, address indexed to, uint256 value);

    event Upgrade(address indexed from, uint256 _value);

    constructor (string memory _name, string memory _symbol) ERC20(_name, _symbol) ERC20Permit(_name) public {
        totalSupplyLimit = 21_000_000 * 10 ** 18;
        //_mint(msg.sender, 1_000_000 * 10 ** 18;
    }

    function readyRule() onlyMinter public {
        require(!ruleReady, "only init once");
        ruleReady = true;
        // GAME, COMMUNITY, FUNDER_AIRPORT, FUNDER, ACTIVE, ADVISORS, PRESALE, PRIVATESALE, PUBLICSALE
        _rules[uint256(RoleType.GAME)].setRule(monthIntervalBlock, 138, 31000000 * 10 ** 18);   // 31000000
        _rules[uint256(RoleType.COMMUNITY)].setRule(monthIntervalBlock, 139, 23000000 * 10 ** 18);     
        _rules[uint256(RoleType.FUNDER_AIRPORT)].setRule(monthIntervalBlock, 830, 1000000 * 10 ** 18); 
        _rules[uint256(RoleType.FUNDER)].setRule(monthIntervalBlock, 137, 16000000 * 10 ** 18); 
        _rules[uint256(RoleType.ACTIVE)].setRule(monthIntervalBlock, 266, 7500000 * 10 ** 18); 
        _rules[uint256(RoleType.ADVISORS)].setRule(monthIntervalBlock, 420, 5000000 * 10 ** 18);  
        _rules[uint256(RoleType.PRESALE)].setRule(monthIntervalBlock, 833, 3600000 * 10 ** 18); 
        _rules[uint256(RoleType.PRIVATESALE)].setRule(monthIntervalBlock, 833, 5040000 * 10 ** 18; 
    }

    function roleType(address account) public view returns (uint256) {
        return uint256(_roles[account]);
    }

    function startBlock(address account) public view returns (uint256) {
        return _freeze_datas[account].startBlock;
    }

    function lastestFreezeBlock(address account) public view returns (uint256) {
        return _freeze_datas[account].lastFreezeBlock;
    }

    function queryFreezeAmount(address account) public view returns(uint256) {
        uint256 lastFreezeBlock = _freeze_datas[account].lastFreezeBlock;
        uint256 startFreezeBlock = _freeze_datas[account].startBlock;
        if(_roles[account] == RoleType.INVALID){
            return 0;
        }
        uint256 amount = _rules[uint256(_roles[account])].freezeAmount(_freeze_datas[account].frozenAmount , startFreezeBlock, lastFreezeBlock, block.number);
        uint256 balance = _frozen_balanceOf(account);
        if(amount > balance) {
            amount = balance;
        }
        if(uint256(_roles[account]) == uint256(RoleType.PRESALE) && !_unusual[account].released) {
           amount = amount + _unusual[account].releaseAmount; 
        }
        return amount;
    }

    function maxTotalSupplyLimit() public view returns(uint256) {
        return totalSupplyLimit;
    }

    function balanceOf(address account) public view override returns (uint256) {
        return balanceOf(account).add(_frozen_balanceOf(account));
    }

    function roleRemainAmount(uint256 _role) public view returns(uint256) {
        return _rules[_role].remainAmount;
    }

    function frozenBalanceOf(address account) public view returns (uint256) {
        return _frozen_balanceOf(account);
    }

    function transferBatch(address[] memory recipients, uint256[] memory amounts) public returns (bool) {
        require(recipients.length > 0, "transferBatch: recipient should be to at least one address");
        require(recipients.length == amounts.length, "transferBatch: recipients and amounts must be equal");
        for (uint256 i = 0; i < recipients.length; i++) {
            _transfer(msg.sender, recipients[i], amounts[i]);
        }
        return true;
    }

    function transferFrozenToken(address to, uint256 amount) public returns (bool) {
        _transferFrozen(msg.sender, to, amount);
        return true;
    }

    function transferBatchFrozenTokens(address[] calldata accounts, uint256[] calldata amounts) external returns (bool) {
        require(accounts.length > 0, "transferBatchFrozenTokens: transfer should be to at least one address");
        require(accounts.length == amounts.length, "transferBatchFrozenTokens: recipients.length != amounts.length");
        for (uint256 i = 0; i < accounts.length; i++) {
            _transferFrozen(msg.sender, accounts[i], amounts[i]);
        }
        return true;
    }

    function meltTokens(address account, uint256 amount) public onlyMinter returns (bool) {
        _melt(account, amount);
        emit Transfer(address(this), account, amount);
        return true;
    }
    
    function meltBatchTokens(address[] calldata accounts, uint256[] calldata amounts) external onlyMinter returns (bool) {
        require(accounts.length > 0, "meltBatchTokens: transfer should be to at least one address");
        require(accounts.length == amounts.length, "meltBatchTokens: accounts.length != amounts.length");
        for (uint256 i = 0; i < accounts.length; i++) {
            _melt(accounts[i], amounts[i]);
            emit Transfer(address(this), accounts[i], amounts[i]);
        }
        return true;
    }

    function mint(address account, uint256 amount) public onlyMinter canMint(amount) returns (bool) {
        _mint(account, amount);
        return true;
    }

    function mintBatchToken(address[] calldata accounts, uint256[] calldata amounts) external onlyMinter canBatchMint(amounts) returns (bool) {
        require(accounts.length > 0, "mintBatchToken: transfer should be to at least one address");
        require(accounts.length == amounts.length, "mintBatchToken: recipients.length != amounts.length");
        for (uint256 i = 0; i < accounts.length; i++) {
            _mint(accounts[i], amounts[i]);
        }

        return true;
    }

    function mintFrozenTokens(address account, uint256 amount) public onlyMinter canMint(amount) returns (bool) {
        _mintfrozen(account, amount);
        return true;
    }

    function mintBatchFrozenTokens(address[] calldata accounts, uint256[] calldata amounts) external onlyMinter canBatchMint(amounts) returns (bool) {
        require(accounts.length > 0, "mintBatchFrozenTokens: transfer should be to at least one address");
        require(accounts.length == amounts.length, "mintBatchFrozenTokens: recipients.length != amounts.length");
        for (uint256 i = 0; i < accounts.length; i++) {
            _mintfrozen(accounts[i], amounts[i]);
        }

        return true;
    }

    function mintFrozenTokensForRole(address account, uint256 amount, RoleType _role) public onlyMinter onlyReady canMint(amount) roleCanMint(uint256(_role), amount) returns (bool) {
        _mintFrozenTokensForRole(account, amount, _role);
        return true;
    }

    function mintBatchFrozenTokensForRole(address[] memory accounts, uint256[] memory amounts, RoleType _role) public onlyMinter onlyReady canBatchMint(amounts)  roleCanBatchMint(uint256(_role), amounts) returns (bool) {
        require(accounts.length > 0, "transfer should be to at least one address");
        require(accounts.length == amounts.length, "recipients.length != amounts.length");
        for (uint256 i = 0; i < accounts.length; i++) {
            _mintFrozenTokensForRole(accounts[i], amounts[i], _role);
        }
        return true;
    }

    // @dev burn erc20 token and exchange mainnet token.
    function upgrade(uint256 amount) public {
        require(amount != 0, "DSGT: upgradable amount should be more than 0");
        address holder = msg.sender;

        // Burn tokens to be upgraded
        _burn(holder, amount);

        // Remember how many tokens we have upgraded
        _totalUpgraded = _totalUpgraded.add(amount);

        // Upgrade agent upgrades/reissues tokens
        emit Upgrade(holder, amount);
    }

    function totalUpgraded() public view returns (uint256) {
        return _totalUpgraded;
    }

    function withdraw(address _token, address payable _recipient) public onlyOwner {
        if (_token == address(0x0)) {
            require(_recipient != address(0x0));
            // transfer eth
            _recipient.transfer(address(this).balance);
            emit Withdrawal(_recipient, address(this).balance);
            return;
        }

        IERC20Token token = IERC20Token(_token);
        uint balance = token.balanceOf(address(this));
        // transfer token
        token.transfer(_recipient, balance);
        emit Withdrawal(_recipient, balance);
    }

    function isContract(address _addr) view internal returns (bool) {
        if (_addr == address(0x0)) return false;
        uint256 size;
        assembly {
            size := extcodesize(_addr)
        }
        return (size > 0);
    }

    function getBlockNumber() internal view returns (uint256) {
        return block.number;
    }

    function claimTokens() public canClaim returns (bool) {
        //Rules.Rule storage rule = _rules[uint256(_roles[msg.sender])];
        uint256 lastFreezeBlock = _freeze_datas[msg.sender].lastFreezeBlock;
        uint256 startFreezeBlock = _freeze_datas[msg.sender].startBlock;
        uint256 amount = _rules[uint256(_roles[msg.sender])].freezeAmount(_freeze_datas[msg.sender].frozenAmount, startFreezeBlock, lastFreezeBlock, block.number);
        if(uint256(_roles[msg.sender]) == uint256(RoleType.PRESALE) && !_unusual[msg.sender].released) ) {
            amount = amount + _unusual[msg.sender].releaseAmount;
            _unusual[msg.sender].released = true;
        }

        require(amount > 0, "Melt amount must be greater than 0");
        // border amount
        if(amount > _frozen_balanceOf(msg.sender)) {
            amount = _frozen_balanceOf(msg.sender);
        }
        _melt(msg.sender, amount); 

        _freeze_datas[msg.sender].lastFreezeBlock = block.number;

        emit Claim(msg.sender, amount);
        return true;
    }

    function startSeedPause() onlyOwner public {
        seedPause = false;
        seedMeltStartBlock = block.number;
    }

    function _mintFrozenTokensForRole(address account, uint256 amount, RoleType _role) internal returns (bool) {
        require(!_freeze_datas[account].initialzed, "specified account already initialzed");
        // set role type
        _roles[account] = _role;
        uint256 startBn = block.number;
        if(_role == RoleType.ADVISORS || _role == RoleType.PRESALE) {
            startBn = startBn + monthIntervalBlock * 3;
        }
        if(_role == RoleType.FUNDER_AIRPORT || _role == RoleType.PRIVATESALE) {
            startBn = startBn + sixMonthIntervalBlock;
        }
        uint256 balance30 = 0;
        if(_role == RoleType.PRESALE){ // 3MONTH 3%
            balance30 = amount * 30 / 100;
            _unusual[account] = Unusual(startBn, balance30, false);
            //amount = amount - balance30;
        }
        _freeze_datas[account] = FreezeData(true, amount - balance30, startBn, startBn);
        _mintfrozen(account, amount);
        return true;
    }

    function _transferFrozen(address sender, address to, uint256 amount) internal {
        require(to != address(0), "ERC20-Frozen: transfer from the zero address");
        require(amount != 0, "ERC20-Frozen: transfer amount is zero");
        require(uint256(_roles[sender]) == uint256(RoleType.COMMUNITY), "ERC20-Frozen: msg.sender is not belong to community");
        require(_frozen_balanceOf(sender) >= amount, "frozen amount should greater than amount");
        _frozen_sub(sender, amount);
        _frozen_add(to, amount);

        emit FrozenTransfer(msg.sender, to, amount);
        emit Transfer(msg.sender, to, amount);
    }

    function _freeze(address account, uint256 amount) internal {
        require(account != address(0), "ERC20: freeze from the zero address");
        require(amount > 0, "ERC20: freeze from the address: amount should be > 0");

        _balances[account] = _balances[account].sub(amount);
        _frozen_add(account, amount);

        emit Freeze(account, amount);
    }

    function _mintfrozen(address account, uint256 amount) internal {
        require(account != address(0), "ERC20: mint frozen to the zero address");
        require(account != address(this), "ERC20: mint frozen to the contract address");
        require(amount > 0, "ERC20: mint frozen amount should be > 0");

        _totalSupply = _totalSupply.add(amount);

        emit Transfer(address(this), account, amount);

        _frozen_add(account, amount);

        emit MintFrozen(account, amount);
    }

    function _melt(address account, uint256 amount) internal {
        require(account != address(0), "ERC20: melt from the zero address");
        require(amount > 0, "ERC20: melt from the address: value should be > 0");
        require(_frozen_balanceOf(account) >= amount, "ERC20: melt from the address: balance < amount");

        _frozen_sub(account, amount);
        _balances[account] = _balances[account].add(amount);

        emit Melt(account, amount);
    }

    function _burnFrozen(address account, uint256 amount) internal {
        require(account != address(0), "ERC20: frozen burn from the zero address");

        _totalSupply = _totalSupply.sub(amount);
        _frozen_sub(account, amount);

        emit Transfer(account, address(this), amount);
    }

    // The following functions are overrides required by Solidity.

    function _afterTokenTransfer(address from, address to, uint256 amount)
        internal
        override(ERC20, ERC20Votes)
    {
        super._afterTokenTransfer(from, to, amount);
    }

    function _mint(address to, uint256 amount)
        internal
        override(ERC20, ERC20Votes)
    {
        super._mint(to, amount);
        require(totalSupply() < totalSupplyLimit, "ELGTToken: total supply risks overflowing max");
    }

    function _burn(address account, uint256 amount)
        internal
        override(ERC20, ERC20Votes)
    {
        super._burn(account, amount);
    }
}
