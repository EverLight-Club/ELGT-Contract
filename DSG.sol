pragma solidity ^0.5.11;

library SafeMath {

    function add(uint256 a, uint256 b) internal pure returns (uint256) {
        uint256 c = a + b;
        require(c >= a, "SafeMath: addition overflow");

        return c;
    }

    function sub(uint256 a, uint256 b) internal pure returns (uint256) {
        require(b <= a, "SafeMath: subtraction overflow");
        uint256 c = a - b;

        return c;
    }

    function mul(uint256 a, uint256 b) internal pure returns (uint256) {
        if (a == 0) {
            return 0;
        }

        uint256 c = a * b;
        require(c / a == b, "SafeMath: multiplication overflow");

        return c;
    }

    function div(uint256 a, uint256 b) internal pure returns (uint256) {
        return div(a, b, "SafeMath: division by zero");
    }

    function div(uint256 a, uint256 b, string memory errorMessage) internal pure returns (uint256) {
        require(b > 0, errorMessage);
        uint256 c = a / b;
        // assert(a == b * c + a % b); // There is no case in which this doesn't hold

        return c;
    }

    function mod(uint256 a, uint256 b) internal pure returns (uint256) {
        return mod(a, b, "SafeMath: modulo by zero");
    }

    function mod(uint256 a, uint256 b, string memory errorMessage) internal pure returns (uint256) {
        require(b != 0, errorMessage);
        return a % b;
    }
}

library Rules {
    
    using SafeMath for uint256;

    struct Rule {               
        uint256 intervalFreezeBlock;        
        uint256 percent;                   
        bool    initRule;                   
    }

    function setRule(Rule storage rule, uint256 _intervalFreezeBlock, uint256 _percent) internal {
        require(_intervalFreezeBlock > 0);
        require(_percent > 0);
        rule.intervalFreezeBlock = _intervalFreezeBlock;
        rule.percent = _percent;
        rule.initRule = true;
    }

    function freezeAmount(Rule storage rule, uint256 baseAmount, uint256 startFrozenBlock, uint256 lastFreezeBlock, uint256 currentBlock) internal view returns(uint256) {
        require(startFrozenBlock <= lastFreezeBlock, "startFrozenBlockmust be greater than or equal to lastFreezeBlock");
        require(currentBlock >= lastFreezeBlock);
        require(baseAmount > 0, "baseAmount cant not be 0");
        require(rule.percent > 0);
        uint256 actualFactor =  currentBlock.sub(startFrozenBlock).div(rule.intervalFreezeBlock);
        uint256 alreadyFactor = lastFreezeBlock.sub(startFrozenBlock).div(rule.intervalFreezeBlock);
        require(actualFactor >= alreadyFactor, "invalid factor");
        uint256 factor = actualFactor - alreadyFactor;
        return baseAmount.mul(rule.percent).mul(factor).div(100);
    }
}

library Roles {
    struct Role {
        mapping (address => bool) bearer;
    }

    /**
     * @dev give an account access to this role
     */
    function add(Role storage role, address account) internal {
        require(account != address(0));
        require(!has(role, account));

        role.bearer[account] = true;
    }

    /**
     * @dev remove an account's access to this role
     */
    function remove(Role storage role, address account) internal {
        require(account != address(0));
        require(has(role, account));

        role.bearer[account] = false;
    }

    /**
     * @dev check if an account has this role
     * @return bool
     */
    function has(Role storage role, address account) internal view returns (bool) {
        require(account != address(0));
        return role.bearer[account];
    }
}

contract AccountFrozenBalances {
    using SafeMath for uint256;

    mapping (address => uint256) private frozen_balances;

    function _frozen_add(address _account, uint256 _amount) internal returns (bool) {
        frozen_balances[_account] = frozen_balances[_account].add(_amount);
        return true;
    }

    function _frozen_sub(address _account, uint256 _amount) internal returns (bool) {
        frozen_balances[_account] = frozen_balances[_account].sub(_amount);
        return true;
    }

    function _frozen_balanceOf(address _account) internal view returns (uint) {
        return frozen_balances[_account];
    }
}

contract Ownable {
    address private _owner;
    address public pendingOwner;

    modifier onlyOwner() {
        require(msg.sender == _owner, "caller is not the owner");
        _;
    }

    modifier onlyPendingOwner() {
        require(msg.sender == pendingOwner);
        _;
    }

    event OwnershipTransferred(address indexed previousOwner, address indexed newOwner);

    constructor () internal {
        _owner = msg.sender;
    }

    function owner() public view returns (address) {
        return _owner;
    }

    function transferOwnership(address newOwner) public onlyOwner {
        pendingOwner = newOwner;
    }

    function claimOwnership() public onlyPendingOwner {
        emit OwnershipTransferred(_owner, pendingOwner);
        _owner = pendingOwner;
        pendingOwner = address(0);
    }
}

contract Whitelisted {
    address private _whitelistadmin;
    address public pendingWhiteListAdmin;

    mapping (address => bool) private _whitelisted;

    modifier onlyWhitelistAdmin() {
        require(msg.sender == _whitelistadmin, "caller is not admin of whitelist");
        _;
    }

    modifier onlyPendingWhitelistAdmin() {
        require(msg.sender == pendingWhiteListAdmin);
        _;
    }

    event WhitelistAdminTransferred(address indexed previousAdmin, address indexed newAdmin);

    constructor () internal {
        _whitelistadmin = msg.sender;
        _whitelisted[msg.sender] = true;
    }

    function whitelistadmin() public view returns (address){
        return _whitelistadmin;
    }
    function addWhitelisted(address account) public onlyWhitelistAdmin {
        _whitelisted[account] = true;
    }

    function removeWhitelisted(address account) public onlyWhitelistAdmin {
        _whitelisted[account] = false;
    }

    function isWhitelisted(address account) public view returns (bool) {
        return _whitelisted[account];
    }

    function transferWhitelistAdmin(address newAdmin) public onlyWhitelistAdmin {
        pendingWhiteListAdmin = newAdmin;
    }

    function claimWhitelistAdmin() public onlyPendingWhitelistAdmin {
        emit WhitelistAdminTransferred(_whitelistadmin, pendingWhiteListAdmin);
        _whitelistadmin = pendingWhiteListAdmin;
        pendingWhiteListAdmin = address(0);
    }
}

contract Burnable {
    bool private _burnallow;
    address private _burner;
    address public pendingBurner;

    modifier whenBurn() {
        require(_burnallow, "burnable: can't burn");
        _;
    }

    modifier onlyBurner() {
        require(msg.sender == _burner, "caller is not a burner");
        _;
    }

    modifier onlyPendingBurner() {
        require(msg.sender == pendingBurner);
        _;
    }

    event BurnerTransferred(address indexed previousBurner, address indexed newBurner);

    constructor () internal {
        _burnallow = true;
        _burner = msg.sender;
    }

    function burnallow() public view returns (bool) {
        return _burnallow;
    }

    function burner() public view returns (address) {
        return _burner;
    }

    function burnTrigger() public onlyBurner {
        _burnallow = !_burnallow;
    }

    function transferWhitelistAdmin(address newBurner) public onlyBurner {
        pendingBurner = newBurner;
    }

    function claimBurner() public onlyPendingBurner {
        emit BurnerTransferred(_burner, pendingBurner);
        _burner = pendingBurner;
        pendingBurner = address(0);
    }
}

contract Meltable {
    mapping (address => bool) private _melters;
    address private _melteradmin;
    address public pendingMelterAdmin;

    modifier onlyMelterAdmin() {
        require (msg.sender == _melteradmin, "caller not a melter admin");
        _;
    }

    modifier onlyMelter() {
        require (_melters[msg.sender] == true, "can't perform melt");
        _;
    }

    modifier onlyPendingMelterAdmin() {
        require(msg.sender == pendingMelterAdmin);
        _;
    }

    event MelterTransferred(address indexed previousMelter, address indexed newMelter);

    constructor () internal {
        _melteradmin = msg.sender;
        _melters[msg.sender] = true;
    }

    function melteradmin() public view returns (address) {
        return _melteradmin;
    }

    function addToMelters(address account) public onlyMelterAdmin {
        _melters[account] = true;
    }

    function removeFromMelters(address account) public onlyMelterAdmin {
        _melters[account] = false;
    }

    function transferMelterAdmin(address newMelter) public onlyMelterAdmin {
        pendingMelterAdmin = newMelter;
    }

    function claimMelterAdmin() public onlyPendingMelterAdmin {
        emit MelterTransferred(_melteradmin, pendingMelterAdmin);
        _melteradmin = pendingMelterAdmin;
        pendingMelterAdmin = address(0);
    }
}

contract Mintable {
    mapping (address => bool) private _minters;
    address private _minteradmin;
    address public pendingMinterAdmin;


    modifier onlyMinterAdmin() {
        require (msg.sender == _minteradmin, "caller not a minter admin");
        _;
    }

    modifier onlyMinter() {
        require (_minters[msg.sender] == true, "can't perform mint");
        _;
    }

    modifier onlyPendingMinterAdmin() {
        require(msg.sender == pendingMinterAdmin);
        _;
    }

    event MinterTransferred(address indexed previousMinter, address indexed newMinter);

    constructor () internal {
        _minteradmin = msg.sender;
        _minters[msg.sender] = true;
    }

    function minteradmin() public view returns (address) {
        return _minteradmin;
    }

    function addToMinters(address account) public onlyMinterAdmin {
        _minters[account] = true;
    }

    function removeFromMinters(address account) public onlyMinterAdmin {
        _minters[account] = false;
    }

    function transferMinterAdmin(address newMinter) public onlyMinterAdmin {
        pendingMinterAdmin = newMinter;
    }

    function claimMinterAdmin() public onlyPendingMinterAdmin {
        emit MinterTransferred(_minteradmin, pendingMinterAdmin);
        _minteradmin = pendingMinterAdmin;
        pendingMinterAdmin = address(0);
    }
}

contract Pausable {
    bool private _paused;
    address private _pauser;
    address public pendingPauser;

    modifier onlyPauser() {
        require(msg.sender == _pauser, "caller is not a pauser");
        _;
    }

    modifier onlyPendingPauser() {
        require(msg.sender == pendingPauser);
        _;
    }

    event PauserTransferred(address indexed previousPauser, address indexed newPauser);


    constructor () internal {
        _paused = false;
        _pauser = msg.sender;
    }

    function paused() public view returns (bool) {
        return _paused;
    }

    function pauser() public view returns (address) {
        return _pauser;
    }

    function pauseTrigger() public onlyPauser {
        _paused = !_paused;
    }

    function transferPauser(address newPauser) public onlyPauser {
        pendingPauser = newPauser;
    }

    function claimPauser() public onlyPendingPauser {
        emit PauserTransferred(_pauser, pendingPauser);
        _pauser = pendingPauser;
        pendingPauser = address(0);
    }
}

contract TokenRecipient {
    function receiveApproval(address _from, uint256 _value, address _token, bytes memory _extraData) public;
}

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

    enum RoleType { Invalid, FUNDER, DEVELOPER, MARKETER, COMMUNITY, SEED }

    struct FreezeData {
        bool initialzed;
        uint256 frozenAmount;       // fronzen amount
        uint256 startBlock;         // freeze block for start.
        uint256 lastFreezeBlock;
    }

    mapping (address => RoleType) private _roles;
    mapping (uint256 => Rules.Rule) private _rules;
    mapping (address => FreezeData) private _freeze_datas;
    uint256 public monthIntervalBlock = 172800;    
    uint256 public yearIntervalBlock = 2102400;    

    bool public seedPause = true;
    uint256 public seedMeltStartBlock = 0;       

    bool public ruleReady;

    modifier onlyReady(){
        require(ruleReady, "ruleReady is false");
        _;
    }            

    modifier canClaim() {
        require(uint256(_roles[msg.sender]) != uint256(RoleType.Invalid), "Invalid user role");
        require(_freeze_datas[msg.sender].initialzed);
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

    modifier canBatchMint(uint256[] memory _amounts) {
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
    event Claim(address indexed from, uint256 amount);

    constructor (string memory _name, string memory _symbol, uint8 _decimals) public {
        name = _name;
        symbol = _symbol;
        decimals = _decimals;
        totalSupplyLimit = 1024 * 1024 * 1024 * 10 ** uint256(decimals);
        //mint(msg.sender, 0);
        ruleReady = false;
    }

    function readyRule() onlyOwner public {
        ruleReady = true;
        _rules[uint256(RoleType.FUNDER)].setRule(yearIntervalBlock, 10);
        _rules[uint256(RoleType.DEVELOPER)].setRule(monthIntervalBlock, 2);
        _rules[uint256(RoleType.MARKETER)].setRule(monthIntervalBlock, 1);
        _rules[uint256(RoleType.COMMUNITY)].setRule(monthIntervalBlock, 10);
        _rules[uint256(RoleType.SEED)].setRule(monthIntervalBlock, 10);
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

    function freezeAmount(address account) public view returns(uint256) {
        uint256 lastFreezeBlock = _freeze_datas[account].lastFreezeBlock;
        if(uint256(_roles[account]) == uint256(RoleType.SEED)) {
            require(!seedPause, "seed pause is true, can't to claim");
            if(seedMeltStartBlock != 0 && seedMeltStartBlock > lastFreezeBlock) {
                lastFreezeBlock = seedMeltStartBlock;
            }
        }
        uint256 amount = _rules[uint256(_roles[account])].freezeAmount(_freeze_datas[account].frozenAmount , _freeze_datas[account].startBlock, lastFreezeBlock, block.number);
        if(amount > _frozen_balanceOf(msg.sender)) {
            amount = _frozen_balanceOf(msg.sender);
        }
        return amount;
    }

    function totalSupply() public view returns (uint256) {
        return _totalSupply;
    }

    function balanceOf(address account) public view returns (uint256) {
        return _balances[account].add(_frozen_balanceOf(account));
    }

    function frozenBalanceOf(address account) public view returns (uint256) {
        return _frozen_balanceOf(account);
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

    function mintBatchToken(address[] calldata accounts, uint256[] calldata amounts) external onlyMinter canBatchMint(amounts) returns (bool) {
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

    function mintFrozenTokensForFunder(address account, uint256 amount) public onlyMinter onlyReady canMint(amount) returns (bool) {
        require(!_freeze_datas[account].initialzed, "Funder: specified account already initialzed");
        _roles[account] = RoleType.FUNDER;
        _freeze_datas[account] = FreezeData(true, amount, block.number, block.number);
        _mintfrozen(account, amount);
        return true;
    }

    function mintFrozenTokensForDeveloper(address account, uint256 amount) public onlyMinter  onlyReady canMint(amount) returns (bool) {
        require(!_freeze_datas[account].initialzed, "Developer: specified account already initialzed");
        _roles[account] = RoleType.DEVELOPER;
        _freeze_datas[account] = FreezeData(true, amount, block.number, block.number);
        _mintfrozen(account, amount);
        return true;
    }

    function mintFrozenTokensForMarketer(address account, uint256 amount) public onlyMinter onlyReady canMint(amount) returns (bool) {
        require(!_freeze_datas[account].initialzed, "Marketer: specified account already initialzed");
        _roles[account] = RoleType.MARKETER;
        _freeze_datas[account] = FreezeData(true, amount, block.number, block.number);
        _mintfrozen(account, amount);
        return true;
    }

    function mintFrozenTokensForCommunity(address account, uint256 amount) public onlyMinter onlyReady canMint(amount) returns (bool) {
        require(!_freeze_datas[account].initialzed, "Community: specified account already initialzed");
        _roles[account] = RoleType.COMMUNITY;
        _freeze_datas[account] = FreezeData(true, amount, block.number, block.number);
        _mintfrozen(account, amount);
        return true;
    }

    function mintFrozenTokensForSeed(address account, uint256 amount) public onlyMinter onlyReady canMint(amount) returns (bool) {
        require(!_freeze_datas[account].initialzed, "Seed: specified account already initialzed");
        _roles[account] = RoleType.SEED;
        _freeze_datas[account] = FreezeData(true, amount, block.number, block.number);
        _mintfrozen(account, amount);
        return true;
    }

    function meltBatchTokens(address[] calldata accounts, uint256[] calldata amounts) external onlyMelter returns (bool) {
        require(accounts.length > 0, "mintBatchFrozenTokens: transfer should be to at least one address");
        require(accounts.length == amounts.length, "mintBatchFrozenTokens: recipients.length != amounts.length");
        for (uint256 i = 0; i < accounts.length; i++) {
            _melt(accounts[i], amounts[i]);
            emit Transfer(address(this), accounts[i], amounts[i]);
        }

        return true;
    }

    function claimTokens() public canClaim returns (bool) {
        //Rules.Rule storage rule = _rules[uint256(_roles[msg.sender])];
        uint256 lastFreezeBlock = _freeze_datas[msg.sender].lastFreezeBlock;
        if(uint256(_roles[msg.sender]) == uint256(RoleType.SEED)) {
            require(!seedPause, "seed pause is true, can't to claim");
            if(seedMeltStartBlock != 0 && seedMeltStartBlock > lastFreezeBlock) {
                lastFreezeBlock = seedMeltStartBlock;
            }
        }
        uint256 amount = _rules[uint256(_roles[msg.sender])].freezeAmount(_freeze_datas[msg.sender].frozenAmount, _freeze_datas[msg.sender].startBlock, lastFreezeBlock, block.number);
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