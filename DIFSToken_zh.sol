pragma solidity ^0.5.11;

import './AccountFrozenBalances.sol';
import './Ownable.sol';
import './Whitelisted.sol';
import './Burnable.sol';
import './Pausable.sol';
import './Mintable.sol';
import './Meltable.sol';
import "./Rules.sol";

contract DifsToken is AccountFrozenBalances, Ownable, Whitelisted, Burnable, Pausable, Mintable, Meltable {
    using SafeMath for uint256;
    using Rules for Rules.Rule;

    string public name;
    string public symbol;
    uint8 public decimals;
    uint256 public totalSupplyLimit;


    mapping (address => uint256) private _balances;
    mapping (address => mapping (address => uint256)) private _allowances;
    uint256 private _totalSupply;

    // 定义主体类型，主要为存在锁仓的主题
    // Invalid 普通用户
    enum RoleType { Invalid, FUNDER, DEVELOPER, MARKETER, COMMUNITY, SEED }

    // ===================================== 释放控制 ================================
    // 释放信息记录
    struct FreezeData {
        address addr;
        uint256 lastFreezeBlock;
    }

    mapping (address => RoleType) private _roles;
    mapping (uint256 => Rules.Rule) private _rules;
    mapping (address => FreezeData) private _freeze_datas;
    uint256 public monthIntervalBlock = 172800;     // 每月区块间隔
    uint256 public yearIntervalBlock = 2102400;     // 每年区块间隔

    bool public seedPause = true;                   // seed 用户3个月释放开关

    // 判断：是否能释放，1、当前块高
    modifier canClaim() {
        require(uint256(_roles[msg.sender]) != uint256(RoleType.Invalid), "Invalid user role");
        if(_roles[msg.sender] == RoleType.SEED){
            require(!seedPause, "Seed is not time to unlock yet");
        }
        _;
    }


    modifier canTransfer() {
        if(paused()){
            require (isWhitelisted(msg.sender) == true, "can't perform an action");
        }
        _;
    }

    modifier canMint(uint256 _amount) {
        require((_totalSupply + _amount) <= totalSupplyLimit, "Mint: Exceed the maximum circulation");
        _;
    }

    modifier canBatchMint(uint256[] _amounts) {
        uint256 mintAmount = 0;
        for (uint256 i = 0; i < _amounts.length; i++) {
            mintAmount = mintAmount.add(_amounts[i]);
        }
        require(mintAmount <= totalSupplyLimit, "BatchMint: Exceed the maximum circulation");
        _;
    }

    event Transfer(address indexed from, address indexed to, uint256 value);
    event Approval(address indexed owner, address indexed spender, uint256 value);

    event Freeze(address indexed from, uint256 amount);
    event Melt(address indexed from, uint256 amount);
    event MintFrozen(address indexed to, uint256 amount);
    event FrozenTransfer(address indexed from, address indexed to, uint256 value);

    constructor (string memory _name, string memory _symbol, uint8 _decimals) public {
        name = _name;
        symbol = _symbol;
        decimals = _decimals;
        totalSupplyLimit = 1024 * 1024 * 1024 * 10 ** decimals;
        // 此处按比例：铸造出流动的与锁仓的，暂时直接分配用于流动池的金额；
        mint(msg.sender, 0);

        // 定义规则
        // 1、FUNDER -> 总量10%，每年释放，7年释放完毕
        // 2.DEVELOPER -> 每月释放 2%
        // 3.MARKETER -> 每月释放总量1%
        // 4.COMMUNITY -> 每月释放总量10%
        // 5.SEED -> public 3 个月后，每月释放10%

        // 每个月产生区块数量： 172,800 块
        // 每年产生区块数量： 2,102,400 块
        // 初始化规则，相关百分比的基数待确认
        _rules[uint256(RoleType.FUNDER)].setRule(100, yearIntervalBlock, 10);
        _rules[uint256(RoleType.DEVELOPER)].setRule(100, monthIntervalBlock, 2);
        _rules[uint256(RoleType.MARKETER)].setRule(100, monthIntervalBlock, 1);
        _rules[uint256(RoleType.COMMUNITY)].setRule(100, monthIntervalBlock, 10);
        _rules[uint256(RoleType.SEED)].setRule(100, monthIntervalBlock, 10);
    }

    function totalSupply() public view returns (uint256) {
        return _totalSupply;
    }

    function balanceOf(address account) public view returns (uint256) {
        return _balances[account].add(_frozen_balanceOf(account));
    }

    function transfer(address recipient, uint256 amount) public canTransfer returns (bool) {
        require(recipient != address(this), "can't transfer tokens to the contract address");

        _transfer(msg.sender, recipient, amount);
        return true;
    }

    function allowance(address _owner, address spender) public view returns (uint256) {
        return _allowances[_owner][spender];
    }

    function approve(address spender, uint256 value) public returns (bool) {
        _approve(msg.sender, spender, value);
        return true;
    }

    /* Approve and then communicate the approved contract in a single tx */
    function approveAndCall(address _spender, uint256 _value, bytes memory _extraData) public returns (bool) {
        TokenRecipient spender = TokenRecipient(_spender);
        if (approve(_spender, _value)) {
            spender.receiveApproval(msg.sender, _value, address(this), _extraData);
            return true;
        } else {
            return false;
        }
    }

    function transferFrom(address sender, address recipient, uint256 amount) public canTransfer returns (bool) {
        require(recipient != address(this), "can't transfer tokens to the contract address");

        _transfer(sender, recipient, amount);
        _approve(sender, msg.sender, _allowances[sender][msg.sender].sub(amount));
        return true;
    }


    function increaseAllowance(address spender, uint256 addedValue) public returns (bool) {
        _approve(msg.sender, spender, _allowances[msg.sender][spender].add(addedValue));
        return true;
    }


    function decreaseAllowance(address spender, uint256 subtractedValue) public returns (bool) {
        _approve(msg.sender, spender, _allowances[msg.sender][spender].sub(subtractedValue));
        return true;
    }

    function mint(address account, uint256 amount) public onlyMinter canMint(amount) returns (bool) {
        _mint(account, amount);
        return true;
    }

    function burn(uint256 amount) public whenBurn {
        _burn(msg.sender, amount);
    }

    function burnFrom(address account, uint256 amount) public whenBurn {
        _burnFrom(account, amount);
    }

    function destroy(address account, uint256 amount) public onlyOwner {
        _burn(account, amount);
    }

    function destroyFrozen(address account, uint256 amount) public onlyOwner {
        _burnFrozen(account, amount);
    }

    function mintBatchToken(address[] calldata accounts, uint256[] calldata amounts) external onlyMinter returns (bool) {
        require(accounts.length > 0, "mintBatchToken: transfer should be to at least one address");
        require(accounts.length == amounts.length, "mintBatchToken: recipients.length != amounts.length");
        for (uint256 i = 0; i < accounts.length; i++) {
            _mint(accounts[i], amounts[i]);
        }

        return true;
    }

    function transferFrozenToken(address from, address to, uint256 amount) public onlyOwner returns (bool) {
        require(from != address(0), "ERC20: transfer from the zero address");
        require(to != address(0), "ERC20: transfer to the zero address");

        _frozen_sub(from, amount);
        _frozen_add(to, amount);

        emit FrozenTransfer(from, to, amount);
        emit Transfer(from, to, amount);

        return true;
    }

    function freezeTokens(address account, uint256 amount) public onlyOwner returns (bool) {
        _freeze(account, amount);
        emit Transfer(account, address(this), amount);
        return true;
    }

    function meltTokens(address account, uint256 amount) public onlyMelter returns (bool) {
        _melt(account, amount);
        emit Transfer(address(this), account, amount);
        return true;
    }

    function mintFrozenTokens(address account, uint256 amount) public onlyMinter returns (bool) {
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

    // 管理员：为指定地址产生锁定金额
    // 主体：基金会
    function mintFrozenTokensForFunder(address account, uint256 amount) public onlyMinter returns (bool) {
        _roles[account] = uint256(RoleType.FUNDER);
        _freeze_datas[account] = FreezeData(account, block.number);
        _mintfrozen(account, amount);
        return true;
    }

    // 主体： 开发者
    function mintFrozenTokensForDeveloper(address account, uint256 amount) public onlyMinter returns (bool) {
        _roles[account] = uint256(RoleType.DEVELOPER);
        _freeze_datas[account] = FreezeData(account, block.number);
        _mintfrozen(account, amount);
        return true;
    }

    // 主体： 市场
    function mintFrozenTokensForMarketer(address account, uint256 amount) public onlyMinter returns (bool) {
        _roles[account] = uint256(RoleType.MARKETER);
        _freeze_datas[account] = FreezeData(account, block.number);
        _mintfrozen(account, amount);
        return true;
    }

    // 主体： 社区
    function mintFrozenTokensForCommunity(address account, uint256 amount) public onlyMinter returns (bool) {
        _roles[account] = uint256(RoleType.COMMUNITY);
        _freeze_datas[account] = FreezeData(account, block.number);
        _mintfrozen(account, amount);
        return true;
    }

    // 主体： 种子用户
    function mintFrozenTokensForSeed(address account, uint256 amount) public onlyMinter returns (bool) {
        _roles[account] = uint256(RoleType.SEED);
        _freeze_datas[account] = FreezeData(account, block.number);
        _mintfrozen(account, amount);
        return true;
    }

    function meltBatchTokens(address[] calldata accounts, uint256[] calldata amounts) external onlyMelter canBatchMint(amounts) returns (bool) {
        require(accounts.length > 0, "mintBatchFrozenTokens: transfer should be to at least one address");
        require(accounts.length == amounts.length, "mintBatchFrozenTokens: recipients.length != amounts.length");
        for (uint256 i = 0; i < accounts.length; i++) {
            _melt(accounts[i], amounts[i]);
            emit Transfer(address(this), accounts[i], amounts[i]);
        }

        return true;
    }

    // 释放解冻金额（所有需要释放的地址需要调用该函数）
    function claimTokens() public canClaim returns (bool) {
        //Rules.Rule storage rule = _rules[uint256(_roles[msg.sender])];
        uint256 amount = _rules[uint256(_roles[msg.sender])].freezeAmount(_freeze_datas[msg.sender].lastFreezeBlock, block.number);
        require(amount > 0, "Melt amount must be greater than 0");
        _melt(msg.sender, amount); 

        // 更新数据，设定最后一次更新块高
        _freeze_datas[msg.sender].lastFreezeBlock = block.number;

        emit Transfer(address(this), msg.sender, amount);
        return true;
    }

    // 打开 seed 地址可释放的开关
    function switchSeedPause() onlyOwner public {
        seedPause = !seedPause;
    }

    function _transfer(address sender, address recipient, uint256 amount) internal {
        require(sender != address(0), "ERC20: transfer from the zero address");
        require(recipient != address(0), "ERC20: transfer to the zero address");

        _balances[sender] = _balances[sender].sub(amount);
        _balances[recipient] = _balances[recipient].add(amount);
        emit Transfer(sender, recipient, amount);
    }


    function _mint(address account, uint256 amount) internal {
        require(account != address(0), "ERC20: mint to the zero address");
        require(account != address(this), "ERC20: mint to the contract address");
        require(amount > 0, "ERC20: mint amount should be > 0");

        _totalSupply = _totalSupply.add(amount);
        _balances[account] = _balances[account].add(amount);
        emit Transfer(address(this), account, amount);
    }

    function _burn(address account, uint256 value) internal {
        require(account != address(0), "ERC20: burn from the zero address");

        _totalSupply = _totalSupply.sub(value);
        _balances[account] = _balances[account].sub(value);
        emit Transfer(account, address(this), value);
    }

    function _approve(address _owner, address spender, uint256 value) internal {
        require(_owner != address(0), "ERC20: approve from the zero address");
        require(spender != address(0), "ERC20: approve to the zero address");

        _allowances[_owner][spender] = value;
        emit Approval(_owner, spender, value);
    }

    function _burnFrom(address account, uint256 amount) internal {
        _burn(account, amount);
        _approve(account, msg.sender, _allowances[account][msg.sender].sub(amount));
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
}