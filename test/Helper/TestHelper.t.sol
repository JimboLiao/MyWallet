// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.17;

import "forge-std/Test.sol";
import { MyWallet } from "../../src/MyWallet.sol";
import { Counter } from "../../src/Counter.sol";
import { MyWalletFactory } from "../../src/MyWalletFactory.sol";

import { EntryPoint } from "account-abstraction/core/EntryPoint.sol";
import { MockERC721 } from "solmate/test/utils/mocks/MockERC721.sol";
import { MockERC1155 } from "solmate/test/utils/mocks/MockERC1155.sol";
import { UserOperation } from "account-abstraction/interfaces/UserOperation.sol";
import { ECDSA } from "openzeppelin/utils/cryptography/ECDSA.sol";

/** 
* @dev we use 3 owners and at least 2 confirm to pass the multisig requirement
* @dev also 3 guardians and at least 2 of their support to recover 
* @dev only 1 address on whiteList
*/ 

contract TestHelper is Test {
    using ECDSA for bytes32;

    uint256 constant INIT_BALANCE = 100 ether;
    uint256 constant ownerNum = 3;
    uint256 constant confirmThreshold = 2;
    uint256 constant guardianNum = 3;
    uint256 constant recoverThreshold = 2;
    uint256 constant timeLimit = 1 days;
    uint256 constant salt = 1;
    address[] owners;
    address[] guardians;
    address[] whiteList;
    uint256 [] ownerKeys;
    uint256 [] guardianKeys;
    bytes32[] guardianHashes;
    address someone;
    address bundler;
    MyWallet wallet;
    MyWalletFactory factory;
    EntryPoint entryPoint;
    Counter counter;
    MockERC721 mockErc721;
    MockERC1155 mockErc1155;

    event SubmitTransaction(address indexed sender, uint256 indexed transactionIndex);
    event ConfirmTransaction(address indexed sender, uint256 indexed transactionIndex);
    event TransactionPassed(uint256 indexed transactionIndex);
    event ExecuteTransaction(uint256 indexed transactionIndex);
    event Receive(address indexed sender, uint256 indexed amount, uint256 indexed balance);
    event SubmitRecovery(address indexed replacedOwner, address indexed newOwner, address proposer);
    event ExecuteRecovery(address indexed oldOwner, address indexed newOwner);
    event AddNewWhiteList(address indexed whiteAddr);
    event RemoveWhiteList(address indexed removeAddr);
    event ReplaceGuardian(bytes32 indexed oldGuardianHash, bytes32 indexed newGuardianHash);
    event FreezeWallet();
    event UnfreezeWallet();

    function setUp() public virtual {
        // setting MyWallet
        setOwners(ownerNum);
        setGuardians();
        for(uint256 i = 0; i < guardianNum; i++) {
            guardianHashes.push(keccak256(abi.encodePacked(guardians[i])));
        }
        address whiteAddr = makeAddr("whiteAddr");
        whiteList.push(whiteAddr);
        someone = makeAddr("someone");
        vm.deal(someone, INIT_BALANCE);
        bundler = makeAddr("bundler");
        vm.deal(bundler, INIT_BALANCE);
        entryPoint = new EntryPoint();
        factory = new MyWalletFactory(entryPoint);
        wallet = factory.createAccount(owners, confirmThreshold, guardianHashes, recoverThreshold, whiteList, salt);
        assertEq(wallet.leastConfirmThreshold(), confirmThreshold);

        // setting test contracts
        counter = new Counter();
        mockErc721 = new MockERC721("MockERC721", "MERC721");
        mockErc1155 = new MockERC1155();

        vm.label(address(wallet), "MyWallet");
        vm.label(address(counter), "counter");
        vm.label(address(mockErc721), "mockERC721");
        vm.label(address(mockErc1155), "mockERC1155");
    }

    // utilities ====================================================
    // make _n owners with INIT_BALANCE
    function setOwners(uint256 _n) internal {
        require(_n > 0, "one owner at least");
        for(uint256 i = 0; i < _n; i++){
            string memory name = string.concat("owner", vm.toString(i));
            (address owner, uint256 privateKey) = makeAddrAndKey(name);
            vm.deal(owner, INIT_BALANCE);
            owners.push(owner);
            ownerKeys.push(privateKey);
        }
    }

    function setGuardians() internal {
        for(uint256 i = 0; i < guardianNum; i++){
            string memory name = string.concat("guardian", vm.toString(i));
            (address guardian, uint256 privateKey) = makeAddrAndKey(name);
            vm.deal(guardian, INIT_BALANCE);
            guardians.push(guardian);
            guardianKeys.push(privateKey);
        }
    }

    // submit transaction to call Counter's increment function
    function submitTx() public returns(bytes memory data, uint256 id){
        data = abi.encodeCall(Counter.increment, ());
        id = wallet.submitTransaction(address(counter), 0, data);
    }

    // submit transaction to send whiteList[0] 1 ether
    function submitTxWhiteList(uint256 amount) public 
    returns(
        bytes memory data,
        uint256 id
    ){
        data = "";
        id = wallet.submitTransaction(whiteList[0], amount, data);
    }

    // submit recovery
    function submitRecovery() public returns(address replacedOwner, address newOwner){
        newOwner = makeAddr("newOwner");
        replacedOwner = owners[2];
        vm.prank(guardians[0]);
        vm.expectEmit(true, true, true, true, address(wallet));
        emit SubmitRecovery(replacedOwner, newOwner, guardians[0]);
        wallet.submitRecovery(replacedOwner, newOwner);
    }

    // sign transaction with private key
    function signTransaction(
        address _to, 
        uint256 _value, 
        bytes memory _data,
        uint256 _nonce,
        uint256 _expiry, 
        uint256 _privateKey
    ) 
        internal 
        view
        returns(uint8 _v, bytes32 _r, bytes32 _s)
    {
        bytes32 domainSeparator = wallet.getDomainSeperator();
        bytes32 transactionTypeHash = wallet.transactionTypeHash();
        bytes32 structHash = keccak256(
            abi.encode(
                transactionTypeHash, 
                _to, 
                _value,
                keccak256(_data),
                _nonce, 
                _expiry));
        bytes32 digest = ECDSA.toTypedDataHash(domainSeparator, structHash);
        (_v, _r, _s) = vm.sign(_privateKey, digest);
    }

    // sign confirm with private key
    function signConfirm(
        uint256 _txIndex,
        uint256 _nonce,
        uint256 _expiry, 
        uint256 _privateKey
    ) 
        internal 
        view
        returns(uint8 _v, bytes32 _r, bytes32 _s)
    {
        bytes32 domainSeparator = wallet.getDomainSeperator();
        bytes32 confirmTypeHash = wallet.confirmTypeHash();
        bytes32 structHash = keccak256(
            abi.encode(
                confirmTypeHash, 
                _txIndex,
                _nonce, 
                _expiry));
        bytes32 digest = ECDSA.toTypedDataHash(domainSeparator, structHash);
        (_v, _r, _s) = vm.sign(_privateKey, digest);
    }

    // sign freeze with private key
    function signFreeze(
        uint256 _nonce, 
        uint256 _expiry, 
        uint256 _privateKey
    ) 
        internal 
        view
        returns(uint8 _v, bytes32 _r, bytes32 _s)
    {
        bytes32 domainSeparator = wallet.getDomainSeperator();
        bytes32 freezeTypeHash = wallet.freezeTypeHash();
        bytes32 structHash = keccak256(abi.encode(freezeTypeHash, _nonce, _expiry));
        bytes32 digest = ECDSA.toTypedDataHash(domainSeparator, structHash);
        (_v, _r, _s) = vm.sign(_privateKey, digest);
    }

    // sign unfreeze with private key
    function signUnfreeze(
        uint256 _nonce, 
        uint256 _expiry, 
        uint256 _privateKey
    ) 
        internal 
        view
        returns(uint8 _v, bytes32 _r, bytes32 _s)
    {
        bytes32 domainSeparator = wallet.getDomainSeperator();
        bytes32 unfreezeTypeHash = wallet.unfreezeTypeHash();
        bytes32 structHash = keccak256(abi.encode(unfreezeTypeHash, _nonce, _expiry));
        bytes32 digest = ECDSA.toTypedDataHash(domainSeparator, structHash);
        (_v, _r, _s) = vm.sign(_privateKey, digest);
    }

    // sign recovery with private key
    function signRecovery(
        address _replacedOwner, 
        address _newOwner, 
        uint256 _nonce, 
        uint256 _expiry, 
        uint256 _privateKey
    ) 
        internal 
        view
        returns(uint8 _v, bytes32 _r, bytes32 _s)
    {
        bytes32 domainSeparator = wallet.getDomainSeperator();
        bytes32 recoveryTypeHash = wallet.recoveryTypeHash();
        bytes32 structHash = keccak256(abi.encode(recoveryTypeHash, _replacedOwner, _newOwner, _nonce, _expiry));
        bytes32 digest = ECDSA.toTypedDataHash(domainSeparator, structHash);
        (_v, _r, _s) = vm.sign(_privateKey, digest);
    }

    // sign support with private key
    function signSupport(uint256 _nonce, uint256 _expiry, uint256 _privateKey) internal view returns(uint8 _v, bytes32 _r, bytes32 _s){
        bytes32 domainSeparator = wallet.getDomainSeperator();
        bytes32 supportTypeHash = wallet.supportTypeHash();
        bytes32 structHash = keccak256(abi.encode(supportTypeHash, _nonce, _expiry));
        bytes32 digest = ECDSA.toTypedDataHash(domainSeparator, structHash);
        (_v, _r, _s) = vm.sign(_privateKey, digest);
    }

    // sign execute recovery with private key
    function signExecuteRecovery(uint256 _nonce, uint256 _expiry, uint256 _privateKey) internal view returns(uint8 _v, bytes32 _r, bytes32 _s){
        bytes32 domainSeparator = wallet.getDomainSeperator();
        bytes32 executeRecoveryTypeHash = wallet.executeRecoveryTypeHash();
        bytes32 structHash = keccak256(abi.encode(executeRecoveryTypeHash, _nonce, _expiry));
        bytes32 digest = ECDSA.toTypedDataHash(domainSeparator, structHash);
        (_v, _r, _s) = vm.sign(_privateKey, digest);
    }

    // create a user operation (not signed yet)
    function createUserOperation(
        address _sender,
        uint256 _nonce,
        bytes memory _initCode,
        bytes memory _callData
    ) 
        internal 
        pure
        returns(UserOperation memory _userOp)
    {
        _userOp.sender = _sender;
        _userOp.nonce = _nonce;
        _userOp.initCode = _initCode;
        _userOp.callData = _callData;
        _userOp.callGasLimit = 600000;
        _userOp.verificationGasLimit = 100000;
        _userOp.preVerificationGas = 10000;
        _userOp.maxFeePerGas = 10000000000;
        _userOp.maxPriorityFeePerGas = 2500000000;
        _userOp.paymasterAndData = "";
    }

    // sign user operation with private key
    function signUserOp(
        UserOperation memory _userOp,
        uint256 _privateKey
    )
        internal
        view
        returns(bytes memory _signature)
    {
        bytes32 userOpHash = entryPoint.getUserOpHash(_userOp);
        bytes32 digest = userOpHash.toEthSignedMessageHash();
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(_privateKey, digest);
        _signature = abi.encodePacked(r, s, v); // note the order here is different from line above.
    }

    // bundler send user operation to entryPoint
    function sendUserOp(UserOperation memory _userOp) public {
        UserOperation[] memory ops;
        ops = new UserOperation[](1);
        ops[0] = _userOp;
        vm.prank(bundler);
        entryPoint.handleOps(ops, payable(bundler));
    }

}