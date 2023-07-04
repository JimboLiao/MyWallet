// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.17;

import "solmate/utils/ReentrancyGuard.sol";
import "openzeppelin/token/ERC721/IERC721Receiver.sol";
import "openzeppelin/token/ERC1155/IERC1155Receiver.sol";

/**
 * @title MyWallet
 * @notice A contract wallet implement features including: multisig, social recovery, 
 *  freeze wallet and whitelist.
 * Note: this is a final project for Appworks school blockchain program #2
 * @author Jimbo
 */
contract MyWallet is ReentrancyGuard, IERC721Receiver, IERC1155Receiver{
    /**********************
     *   enum 
     **********************/
    ///@notice transaction status for multisig
    enum TransactionStatus {
        PENDING,
        PASS,
        EXECUTED,
        OVERTIME
    }

    /**********************
     *   struct
     **********************/ 
    ///@notice transaction infomation
    struct Transaction {
        TransactionStatus status;
        address to; // target address to call
        uint256 value; // value with the transaction
        uint256 confirmNum; // confirmed number of multisig
        uint256 untilTimestamp; // timelimit to pass the transaction
        bytes data; // calldata
    }

    ///@notice Recovery infomation
    struct Recovery {
        address newOwner; // new owner after recovery
        uint256 replacedOwnerIndex; // index of owner to be replaced
        uint256 supportNum; // number of support recovery
    }

    /**********************
     *   constant 
     **********************/
    ///@notice A time limit for multisig
    uint256 public constant overTimeLimit = 1 days;

    /**********************
     *   variables
     **********************/
    /// @notice true if wallet is frozen
    bool public isFreezing;

    /// @notice true if wallet is in recovery process
    bool public isRecovering;

    address[] internal owners;
    // todo need this?
    address[] internal whiteList;

    /// @notice guardian hashes to hide the id of guardians undil recovery
    // todo need this?
    bytes32[] internal guardianHashes;

    /// @notice record every transaction submitted
    Transaction[] internal transactionList;

    /// @notice submitted recovery infomation
    Recovery internal recoveryProposed;

    /// @notice threshold for multisig and unfreeze
    uint256 public leastConfirmThreshold;

    /// @notice threshold for recovery
    uint256 public recoverThreshold;

    mapping(address => bool) public isOwner;
    mapping(address => bool) public isWhiteList;
    mapping(bytes32 => bool) public isGuardian;
    uint256 public unfreezeCounter;
    /// @notice current round of freeze
    uint256 public unfreezeRound;

    /// @notice current round of recovery
    uint256 public recoverRound;

    /// @notice true if already confirm tx
    /// @dev tx index => owner address => bool
    mapping(uint256 => mapping(address => bool)) public isConfirmed;

    /// @notice true if already unfreeze by owner
    /// @dev unfreezeRound => owner address => bool
    mapping(uint256 => mapping(address => bool)) public unfreezeBy;

    /// @notice true if already support recovery by guardian
    /// @dev recoveryRound => guardian address => bool
    mapping(uint256 => mapping(address => bool)) public recoverBy;

    /**********************
     *   events 
     **********************/
    /// @notice emitted when owner confirm a tx
    event ConfirmTransaction(address indexed sender, uint256 indexed transactionIndex);

    /// @notice emitted when transaction with transactionIndex passed
    event TransactionPassed(uint256 indexed transactionIndex);

    /// @notice emitted when a tx excuted
    event ExecuteTransaction(uint256 indexed transactionIndex);

    /// @notice emitted when wallet receive ether
    event Receive(address indexed sender, uint256 indexed amount, uint256 indexed balance);

    /// @notice emitted when guardian submit recovery
    event SubmitRecovery(uint256 indexed replacedOwnerIndex, address indexed newOwner, address proposer);

    /// @notice emitted when owner execute recovery
    event ExecuteRecovery(address indexed oldOwner, address indexed newOwner);

    /// @notice emitted when add a new white list
    event AddNewWhiteList(address indexed whiteAddr);

    /// @notice emitted when remove a address from white list
    event RemoveWhiteList(address indexed removeAddr);

    /// @notice emitted when replace a guardian
    event ReplaceGuardian(bytes32 indexed oldGuardianHash, bytes32 indexed newGuardianHash);

    /// @notice emitted when freeze wallet
    event FreezeWallet();

    /// @notice emitted when wallet unfreeze succefully
    event UnfreezeWallet();

    /**********************
     *   errors
     **********************/
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
    error NotFromWallet();
    error StatusNotPass();
    error TxAlreadyConfirmed();
    error TxAlreadyExecutedOrOverTime();
    error WalletFreezing();
    error WalletIsNotFrozen();
    error SupportNumNotEnough();
    error NoOwnerOrGuardian();
    error InvalidThreshold();
    error NotOnWhiteList();

    /* modifiers */
    modifier onlyOwner(){
        if(!isOwner[msg.sender]){
            revert NotOwner();
        }
        _;
    }

    modifier onlyGuardian() {
        if(!isGuardian[keccak256(abi.encodePacked(msg.sender))]){
            revert NotGuardian();
        }
        _;
    }

    /**
     * @dev for functions designed to be called by executeTransaction
     */
    modifier onlyExecuteByWallet() {
        if(msg.sender != address(this)){
            revert NotFromWallet();
        }
        _;
    }

    /**********************
     *   constructor
     **********************/
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
                _addWhiteList(whiteAddr);
            }
        }
    }

    /**********************
     *   receive
     **********************/
    receive() external payable {
        emit Receive(msg.sender, msg.value, address(this).balance);
    }

    /************************
     *   multisig functions
     ************************/

    /**
     * @notice owner submit transactions before multisig
     * @param  _to is the tartget address
     * @param _value is the value with the tx
     * @param _data is the calldata of the tx
     */
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
    }

    /**
     * @notice get transaction information
     * @param _transactionIndex is the index of transactionList
     */
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

    /**
     * @notice confirm transaction to pass multisig process
     * @dev tx status will be PASS if tx's to address is on white list or the confirmNum > threshold
     */
    function confirmTransaction(uint256 _transactionIndex)
        public
        onlyOwner
    {
        _isIndexValid(_transactionIndex);
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
            ++txn.confirmNum >= leastConfirmThreshold || // over threshold
            isWhiteList[txn.to] // on white list
        ){
            txn.status = TransactionStatus.PASS;
            emit TransactionPassed(_transactionIndex);
        }
        // else, txn.status remains PENDING
        emit ConfirmTransaction(msg.sender, _transactionIndex);
    }

    /**
     * @notice Execute the transaction
     * @dev everyone can call this, only passed transaction can be executed
     * @dev revert if wallet is freezing
     */ 
    function executeTransaction(uint256 _transactionIndex) 
        public
        nonReentrant
    {
        _isIndexValid(_transactionIndex);
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

    /**
     * @notice get transaction's status
     * @param _transactionIndex index of transactionList
     */
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

    /**
     * @notice check if transaction index valid
     */
    function _isIndexValid(uint256 _transactionIndex) internal view{
        if(_transactionIndex >= transactionList.length){
            revert InvalidTransactionIndex();
        }
    }

    /************************
     *   Recovery functions
     ************************/
    /**
     * @notice guardian submit recovery
     * @param _replacedOwnerIndex the index of owners to be replaced
     * @param _newOwner address of new owner
     */
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

    /**
     * @notice guardian support recovery
     */
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

    /**
     * @notice execute recovery
     * @dev only owner can execute recovery after support num >= recoverThreshold
     */
    function executeRecovery() public onlyOwner {
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

    /**
     * @notice get Recovery informations
     */
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

    /************************
     *   Freeze functions
     ************************/

    /**
     * @notice freeze wallet
     */
    function freezeWallet() external onlyOwner {
        isFreezing = true;

        emit FreezeWallet();
    }

    /**
     * @notice unfreeze wallet
     * @dev the wallet will not unfreeze until unfreezeCounter >= leastConfirmThreshold
     */
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

            emit UnfreezeWallet();
        }
    }

    /************************
     *   Argument functions
     ************************/

    /**
     * @notice add a new address to whiteList
     * @param _whiteAddr address to be added
     * @dev only execute by executeTransaction, which means pass the multisig
     */
    function addWhiteList(address _whiteAddr) external onlyExecuteByWallet{
        _addWhiteList(_whiteAddr);
    }

    function _addWhiteList(address _whiteAddr) internal {
        // address(0) and wallet cannot on the whiteList
        if(
            _whiteAddr == address(this) ||
            _whiteAddr == address(0)
        ){
            revert InvalidAddress();
        }

        if(isWhiteList[_whiteAddr]){
            revert AlreadyOnWhiteList(_whiteAddr);
        }

        isWhiteList[_whiteAddr] = true;
        whiteList.push(_whiteAddr);

        emit AddNewWhiteList(_whiteAddr);
    }
    
    /**
     * @notice remove address from whiteList
     * @param _removeAddr address to be removed
     * @dev only execute by executeTransaction, which means pass the multisig
     */
    function removeWhiteList(address _removeAddr) external onlyExecuteByWallet{
        _removeWhiteList(_removeAddr);
    }

    function _removeWhiteList(address _removeAddr) internal {
        if(!isWhiteList[_removeAddr]){
            revert NotOnWhiteList();
        }

        isWhiteList[_removeAddr] = false;
        // todo is array whiteList necessary?

        emit RemoveWhiteList(_removeAddr);
    }

    /**
     * @notice replace guardian
     * @param _oldGuardianHash hash of old guardian's address
     * @param _newGuardianHash hash of new guardian's address
     * @dev only execute by executeTransaction, which means pass the multisig
     */
    function replaceGuardian(bytes32 _oldGuardianHash, bytes32 _newGuardianHash) external onlyExecuteByWallet{
        // cannot replace a guardian while recovering
        if(isRecovering){
            revert WalletIsRecovering();
        }

        if(!isGuardian[_oldGuardianHash]){
            revert NotGuardian();
        }

        isGuardian[_oldGuardianHash] = false;
        isGuardian[_newGuardianHash] = true;
        // todo is array guardianHashes necessary?

        emit ReplaceGuardian(_oldGuardianHash, _newGuardianHash);
    }


    /************************
     *   Receive Tokens
     ************************/
    /**
     * @notice IERC721Receiver
     */
    function onERC721Received(address, address, uint256, bytes memory) public pure override returns (bytes4) {
        return this.onERC721Received.selector;
    }

    /**
     * @notice IERC1155Receiver
     */
    function onERC1155Received(address, address, uint256, uint256, bytes calldata) external pure returns (bytes4) {
        return this.onERC1155Received.selector;
    }

    /**
     * @notice IERC1155Receiver
     */
    function onERC1155BatchReceived(address, address, uint256[] calldata, uint256[] calldata, bytes calldata) 
        external pure returns (bytes4) {
        return this.onERC1155BatchReceived.selector;
    }

    /**
     * @dev Support for EIP 165
     */
    function supportsInterface(bytes4 interfaceId) external pure returns (bool) {
        if (
            interfaceId == 0x01ffc9a7 || // ERC165 interfaceID
            interfaceId == 0x150b7a02 || // ERC721TokenReceiver interfaceID
            interfaceId == 0x4e2312e0 // ERC1155TokenReceiver interfaceID
        ) {
            return true;
        }
        return false;
    }
}