// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.17;

contract MyWallet {
    /* enum */
    enum TransactionStatus {
        PENDING,
        PASS,
        EXECUTED,
        OVERTIME
    }

    /* struct */
    struct Transaction {
        TransactionStatus status;
        address to;
        uint256 value;
        bytes data;
        uint256 confirmNum;
        uint256 untilTimestamp;
    }

    struct Recovery {
        uint256 replacedOwnerIndex;
        address newOwner;
        uint256 supportNum;
    }

    /* state variables */
    uint256 public constant overTimeLimit = 1 days;
    address[] internal whiteList;
    address[] internal owners;
    bytes32[] internal guardianHashes;
    Transaction[] internal transactionList;
    Recovery internal recoveryProposed;
    uint256 public leastConfirmThreshold;
    uint256 public recoverThreshold;
    mapping(address => bool) public isOwner;
    mapping(address => bool) public isWhiteList;
    mapping(bytes32 => bool) public isGuardian;
    mapping(uint256 => mapping(address => bool)) public isConfirmed;
    bool public isFreezing;
    bool public isRecovering;
    uint256 public unfreezeCounter;
    uint256 public unfreezeRound;
    uint256 public recoverRound;
    mapping(uint256 => mapping(address => bool)) public unfreezeBy;
    mapping(uint256 => mapping(address => bool)) public recoverBy;

    /* events */
    event ConfirmTransaction(address indexed sender, uint256 indexed transactionIndex);
    event ExecuteTransaction(uint256 indexed transactionIndex);
    event Receive(address indexed sender, uint256 indexed amount, uint256 indexed balance);
    event SubmitRecovery(uint256 indexed replacedOwnerIndex, address indexed newOwner, address proposer);
    event ExecuteRecovery(address indexed oldOwner, address indexed newOwner);

    /* errors */
    error AlreadyUnfreezeBy(address addr);
    error AlreadyRecoverBy(address addr);
    error AlreadyAnOwner(address addr);
    error AlreadyOnWhiteList(address addr);
    error AlreadyAGuardian(bytes32 guardianHash);
    error InvalidAddress();
    error ExecuteFailed();
    error InvalidTransactionIndex();
    error WalletIsRecovering();
    error WalletIsNotRecovering();
    error NotOwner();
    error NotGuardian();
    error StatusNotPass();
    error TxAlreadyConfirmed();
    error TxAlreadyExecutedOrOverTime();
    error WalletFreezing();
    error WalletIsNotFrozen();
    error SupportNumNotEnough();
    error NoOwnerOrGuardian();
    error InvalidThreshold();

    /* modifiers */
    modifier onlyOwner(){
        if(!isOwner[msg.sender]){
            revert NotOwner();
        }
        _;
    }

    modifier isIndexValid(uint256 _transactionIndex){
        if(_transactionIndex >= transactionList.length){
            revert InvalidTransactionIndex();
        }
        _;
    }

    modifier onlyGuardian() {
        if(!isGuardian[keccak256(abi.encodePacked(msg.sender))]){
            revert NotGuardian();
        }
        _;
    }

    /* functions */
    /* constructor */
    constructor(
        address[] memory _owners,
        uint256 _leastConfirmThreshold,
        bytes32[] memory _guardianHashes,
        uint256 _recoverThreshold,
        address[] memory _whiteList
    )
    {
        if(_owners.length == 0 || _guardianHashes.length == 0) {
            revert NoOwnerOrGuardian();
        }

        if(
            _leastConfirmThreshold == 0 ||
            _recoverThreshold == 0 ||
            _leastConfirmThreshold > _owners.length ||
            _recoverThreshold > _guardianHashes.length
        ){
            revert InvalidThreshold();
        }

        // owners
        for (uint256 i = 0; i < _owners.length; i++) {
            address owner = _owners[i];

            if(owner == address(0)){
                revert InvalidAddress();
            }

            if(isOwner[owner]){
                revert AlreadyAnOwner(owner);
            }

            isOwner[owner] = true;
            owners.push(owner);
        }

        leastConfirmThreshold = _leastConfirmThreshold;

        // guardian hashes
        for (uint256 i = 0; i < _guardianHashes.length; i++) {
            bytes32 h = _guardianHashes[i];

            if(isGuardian[h]){
                revert AlreadyAGuardian(h);
            }

            isGuardian[h] = true;
            guardianHashes.push(h);
        }

        recoverThreshold = _recoverThreshold;

        // whitelist, if any
        if(_whiteList.length > 0){
            for (uint256 i = 0; i < _whiteList.length; i++) {
                address whiteAddr = _whiteList[i];

                if(whiteAddr == address(0)){
                    revert InvalidAddress();
                }

                if(isWhiteList[whiteAddr]){
                    revert AlreadyOnWhiteList(whiteAddr);
                }

                isWhiteList[whiteAddr] = true;
                whiteList.push(whiteAddr);
            }
        }
    }

    /* receive function */
    receive() external payable {
        emit Receive(msg.sender, msg.value, address(this).balance);
    }

    /* external functions */
    function submitTransaction(
        address _to,
        uint256 _value,
        bytes calldata _data
    )
        external
        onlyOwner
        returns(uint256 _transactionIndex)
    {
        _transactionIndex = transactionList.length;
        transactionList.push(
            Transaction({
                status: TransactionStatus.PENDING,
                to: _to,
                value: _value,
                data: _data,
                confirmNum: 0,
                untilTimestamp: block.timestamp + overTimeLimit
            })
        );
        // auto confirm transaction for who submit the transaction
        confirmTransaction(_transactionIndex);
    }

    function getTransactionInfo(uint256 _transactionIndex)
        external
        view
        returns(
            TransactionStatus,
            address,
            uint256,
            bytes memory,
            uint256,
            uint256
        )
    {
        Transaction storage txn = transactionList[_transactionIndex];
        return (
            _getTransactionStatus(_transactionIndex),
            txn.to,
            txn.value,
            txn.data,
            txn.confirmNum,
            txn.untilTimestamp
        );
    }

    function getRecoveryInfo() external view 
        returns(
            uint256, 
            address, 
            uint256
        )
    {
        return (
            recoveryProposed.replacedOwnerIndex,
            recoveryProposed.newOwner,
            recoveryProposed.supportNum
        );
    }

    function freezeWallet() external onlyOwner {
        isFreezing = true;
    }

    function unfreezeWallet() external onlyOwner {
        if(!isFreezing){
            revert WalletIsNotFrozen();
        }

        if(unfreezeBy[unfreezeRound][msg.sender]){
            revert AlreadyUnfreezeBy(msg.sender);
        }

        unfreezeBy[unfreezeRound][msg.sender] = true;
        if(++unfreezeCounter >= leastConfirmThreshold){
            isFreezing = false;
            // start a new round for the next time
            ++unfreezeRound;
            unfreezeCounter = 0;
        }
    }

    function submitRecovery(
        uint256 _replacedOwnerIndex,
        address _newOwner
    )
        external
        onlyGuardian
    {
        if(isRecovering){
            revert WalletIsRecovering();
        }

        if(_newOwner == address(0)){
            revert InvalidAddress();
        }

        if(isOwner[_newOwner]){
            revert AlreadyAnOwner(_newOwner);
        }

        isRecovering = true;
        recoveryProposed.replacedOwnerIndex = _replacedOwnerIndex;
        recoveryProposed.newOwner = _newOwner;
        recoveryProposed.supportNum = 0;
        emit SubmitRecovery(_replacedOwnerIndex, _newOwner, msg.sender);
    }

    /* public functions */
    function confirmTransaction(uint256 _transactionIndex)
        public
        onlyOwner
        isIndexValid(_transactionIndex)
    {
        // already confirmed
        if(isConfirmed[_transactionIndex][msg.sender]){
            revert TxAlreadyConfirmed();
        }

        TransactionStatus status= _getTransactionStatus(_transactionIndex);
        // EXECUTED or OVERTIME
        if(
            status == TransactionStatus.EXECUTED ||
            status == TransactionStatus.OVERTIME
        ){
            revert TxAlreadyExecutedOrOverTime();
        }

        Transaction storage txn = transactionList[_transactionIndex];
        isConfirmed[_transactionIndex][msg.sender] = true;
        // PASS
        if(
            ++txn.confirmNum >= leastConfirmThreshold || 
            isWhiteList[txn.to]
        ){
            txn.status = TransactionStatus.PASS;
        }
        // else, txn.status remains PENDING
        emit ConfirmTransaction(msg.sender, _transactionIndex);
    }

    /// @notice Execute the transaction
    /// @dev everyone can call this
    function executeTransaction(uint256 _transactionIndex) 
        public
        isIndexValid(_transactionIndex)
    {
        if(isFreezing){
            revert WalletFreezing();
        }

        Transaction storage txn = transactionList[_transactionIndex];
        if(txn.status != TransactionStatus.PASS){
            revert StatusNotPass();
        }

        txn.status = TransactionStatus.EXECUTED;
        (bool success, ) = txn.to.call{value: txn.value}(txn.data);
        if(!success){
            revert ExecuteFailed();
        }

        emit ExecuteTransaction(_transactionIndex);
    }

    function supportRecovery() public onlyGuardian{
        if(!isRecovering){
            revert WalletIsNotRecovering();
        }

        if(recoverBy[recoverRound][msg.sender]){
            revert AlreadyRecoverBy(msg.sender);
        }

        recoverBy[recoverRound][msg.sender] = true;
        ++recoveryProposed.supportNum;
    }

    function executeRecovery() public onlyOwner{
        if(!isRecovering){
            revert WalletIsNotRecovering();
        }

        if(recoveryProposed.supportNum < recoverThreshold){
            revert SupportNumNotEnough();
        }

        // change owner
        uint256 idx = recoveryProposed.replacedOwnerIndex;
        address oldOwner = owners[idx];
        address newOwner = recoveryProposed.newOwner;
        isOwner[oldOwner] = false;
        isOwner[newOwner] = true;
        owners[idx] = newOwner;

        // initial for next time
        isRecovering = false;
        ++recoverRound;
        delete recoveryProposed;

        emit ExecuteRecovery(oldOwner, newOwner);
    }

    /* internal functions */
    function _getTransactionStatus(uint256 _transactionIndex) internal view returns(TransactionStatus){
        Transaction storage txn = transactionList[_transactionIndex];
        // EXECUTED
        if(txn.status == TransactionStatus.EXECUTED){
            return TransactionStatus.EXECUTED;
        }
        // OVERTIME
        if(block.timestamp > txn.untilTimestamp){
            return TransactionStatus.OVERTIME;
        }
        // PENDING or PASS
        return txn.status;
    }

    /* private functions */
}