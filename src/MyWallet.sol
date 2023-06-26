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
        uint256 proposedTimestamp;
    }

    /* state variables */
    uint256 public constant overTimeLimit = 1 days;

    address[] internal owners;
    Transaction[] internal transactionList;
    uint256 public leastConfirmThreshold;
    mapping(address => bool) public isOwner;
    mapping(uint256 => mapping(address => bool)) public isConfirmed;

    /* events */
    event ConfirmTransaction(address indexed sender, uint256 indexed transactionIndex);
    event ExecuteTransaction(uint256 indexed transactionIndex);
    event Receive(address indexed sender, uint256 indexed amount, uint256 indexed balance);
    
    /* errors */
    error ExecuteFailed();
    error InvalidTransactionIndex();
    error NotOwner();
    error StatusNotPass();
    error TxAlreadyConfirmed();
    error TxAlreadyExecutedOrOverTime();

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

    /* functions */
    /* constructor */
    constructor(
        address[] memory _owners,
        uint256 _leastConfirmThreshold
    )
    {
        require(_owners.length > 0, "No owner assigned");
        require(_owners.length <= 5, "Too many owners");
        require(
            _leastConfirmThreshold <= _owners.length && _leastConfirmThreshold > 0,
            "Invalid confirm threshold"
        );

        for (uint256 i = 0; i < _owners.length; i++) {
            address owner = _owners[i];

            require(owner != address(0), "Invalid owner");
            require(!isOwner[owner], "Already is a owner");

            isOwner[owner] = true;
            owners.push(owner);
        }

        leastConfirmThreshold = _leastConfirmThreshold;
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
                proposedTimestamp: block.timestamp
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
        TransactionStatus status = _getTransactionStatus(_transactionIndex);

        return (
            status,
            txn.to,
            txn.value,
            txn.data,
            txn.confirmNum,
            txn.proposedTimestamp
        );
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
        if(++txn.confirmNum >= leastConfirmThreshold){
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

    /* internal functions */
    function _getTransactionStatus(uint256 _transactionIndex) internal view returns(TransactionStatus){
        Transaction storage txn = transactionList[_transactionIndex];
        // EXECUTED
        if(txn.status == TransactionStatus.EXECUTED){
            return TransactionStatus.EXECUTED;
        }
        // OVERTIME
        if(block.timestamp > txn.proposedTimestamp + overTimeLimit){
            return TransactionStatus.OVERTIME;
        }
        // PENDING or PASS
        return txn.status;
    }

    /* private functions */
}