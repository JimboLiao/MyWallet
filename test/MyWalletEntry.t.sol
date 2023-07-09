// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.17;

import { TestHelper } from "./Helper/TestHelper.t.sol";
import { Counter } from "../src/Counter.sol";
import { MyWallet } from "../src/MyWallet.sol";
import { MyWalletStorage } from "../src/MyWalletStorage.sol";
import { UserOperation } from "account-abstraction/interfaces/UserOperation.sol";
import { ECDSA } from "openzeppelin/utils/cryptography/ECDSA.sol";
import { IEntryPoint} from "account-abstraction/interfaces/IEntryPoint.sol";
import "forge-std/console.sol";

/** 
 * @dev test interact with MyWallet through EntryPoint
 */ 

contract MyWalletEntryTest is TestHelper {
    using ECDSA for bytes32;
    address bundler;

    function setUp() public override {
        super.setUp();

        bundler = makeAddr("bundler");
        vm.deal(bundler, INIT_BALANCE);

        // deposit eth for wallet
        vm.prank(owners[0]);
        entryPoint.depositTo{value: 5 ether}(address(wallet));
        assertEq(entryPoint.balanceOf(address(wallet)), 5 ether);
    }

    function testEntrySimulateValidation() public {
        // create userOperation
        vm.startPrank(owners[0]);
        address sender = address(wallet);
        uint256 nonce = wallet.getNonce();
        bytes memory initCode = "";
        bytes memory callData = abi.encodeCall(
            MyWallet.submitTransaction, 
            (
                address(counter), 
                0, 
                abi.encodeCall(Counter.increment, ())
            ));
        UserOperation memory userOp = createUserOperation(sender, nonce, initCode, callData);
        // sign 
        userOp.signature = signUserOp(userOp, ownerKeys[0]);
        vm.stopPrank();

        // bundler simulate Operation
        // Successful result is ValidationResult error.
        vm.startPrank(bundler);
        vm.expectRevert();
        entryPoint.simulateValidation(userOp); // should be done offchain
        // "ValidationResult((58755, 7100000000000000, false, 0, 281474976710655, 0x), (0, 0), (0, 0), (0, 0))"
        vm.stopPrank();
    }

    function testEntrySubmitTransaction() public {
        // create userOperation
        vm.startPrank(owners[0]);
        address sender = address(wallet);
        uint256 nonce = wallet.getNonce();
        bytes memory initCode = "";
        bytes memory callData = abi.encodeCall(
            MyWallet.submitTransaction, 
            (
                address(counter), 
                0, 
                abi.encodeCall(Counter.increment, ())
            ));
        UserOperation memory userOp = createUserOperation(sender, nonce, initCode, callData);
        // sign 
        userOp.signature = signUserOp(userOp, ownerKeys[0]);
        vm.stopPrank();

        UserOperation[] memory ops;
        ops = new UserOperation[](1);
        ops[0] = userOp;

        // bundler send operation to entryPoint
        vm.prank(bundler);
        entryPoint.handleOps(ops, payable(bundler));

        // check effects
        (MyWallet.TransactionStatus status, 
        address to, 
        uint256 value, 
        bytes memory data, 
        uint256 confirmNum, 
        uint256 timestamp) = wallet.getTransactionInfo(0);
        require(status == MyWalletStorage.TransactionStatus.PENDING, "status error");
        assertEq(to, address(counter));
        assertEq(value, 0);
        assertEq(data, abi.encodeCall(Counter.increment, ()));
        assertEq(confirmNum, 0);
        assertEq(timestamp, block.timestamp + timeLimit);
    }

    function testConfirmTransaction() public {
        testEntrySubmitTransaction();
        // create userOperation
        vm.startPrank(owners[0]);
        address sender = address(wallet);
        uint256 nonce = wallet.getNonce();
        bytes memory initCode = "";
        bytes memory callData = abi.encodeCall(MyWallet.confirmTransaction, (0));
        UserOperation memory userOp = createUserOperation(sender, nonce, initCode, callData);
        // sign 
        userOp.signature = signUserOp(userOp, ownerKeys[0]);
        vm.stopPrank();

        UserOperation[] memory ops;
        ops = new UserOperation[](1);
        ops[0] = userOp;

        // bundler send operation to entryPoint
        vm.prank(bundler);
        entryPoint.handleOps(ops, payable(bundler));

        // check effects
        (, , , , uint256 confirmNum, ) = wallet.getTransactionInfo(0);
        assertEq(confirmNum, 1);
        assertTrue(wallet.isConfirmed(0, owners[0]));
    }

    function testEntryExecuteTransaction() public {
        testConfirmTransaction();
        // confirm by owners[1]
        vm.startPrank(owners[1]);
        wallet.confirmTransaction(0);
        vm.stopPrank();

        // create userOperation
        vm.startPrank(owners[0]);
        address sender = address(wallet);
        uint256 nonce = wallet.getNonce();
        bytes memory initCode = "";
        bytes memory callData = abi.encodeCall(MyWallet.executeTransaction, (0));
        UserOperation memory userOp = createUserOperation(sender, nonce, initCode, callData);
        // sign 
        userOp.signature = signUserOp(userOp, ownerKeys[0]);
        vm.stopPrank();

        UserOperation[] memory ops;
        ops = new UserOperation[](1);
        ops[0] = userOp;

        // bundler send operation to entryPoint
        vm.prank(bundler);
        entryPoint.handleOps(ops, payable(bundler));

        // check effects
        assertEq(counter.number(), 1);
    }

    function testEntrySubmitRecovery() public {
        // create userOperation
        vm.startPrank(guardians[0]);
        address sender = address(wallet);
        uint256 nonce = wallet.getNonce();
        bytes memory initCode = "";
        bytes memory callData = abi.encodeCall(MyWallet.submitRecovery, (owners[2], someone));
        UserOperation memory userOp = createUserOperation(sender, nonce, initCode, callData);
        // sign 
        userOp.signature = signUserOp(userOp, guardianKeys[0]);
        vm.stopPrank();

        UserOperation[] memory ops;
        ops = new UserOperation[](1);
        ops[0] = userOp;

        // bundler send operation to entryPoint
        vm.prank(bundler);
        entryPoint.handleOps(ops, payable(bundler));

        // check effects
        (address addr1, address addr2, uint256 num) = wallet.getRecoveryInfo();
        assertEq(addr1, owners[2]);
        assertEq(addr2, someone);
        assertEq(num, 0);
        assertTrue(wallet.isRecovering());
    }

    function testEntrySupportRecovery() public {
        testEntrySubmitRecovery();
        // create userOperation
        vm.startPrank(guardians[0]);
        address sender = address(wallet);
        uint256 nonce = wallet.getNonce();
        bytes memory initCode = "";
        bytes memory callData = abi.encodeCall(MyWallet.supportRecovery, ());
        UserOperation memory userOp = createUserOperation(sender, nonce, initCode, callData);
        // sign 
        userOp.signature = signUserOp(userOp, guardianKeys[0]);
        vm.stopPrank();

        UserOperation[] memory ops;
        ops = new UserOperation[](1);
        ops[0] = userOp;

        // bundler send operation to entryPoint
        vm.prank(bundler);
        entryPoint.handleOps(ops, payable(bundler));

        // check effects
        (, , uint256 num) = wallet.getRecoveryInfo();
        assertEq(num, 1);
        assertTrue(wallet.recoverBy(0, guardians[0]));
    }

    function testEntryExecuteRecovery() public {
        testEntrySupportRecovery();

        vm.prank(guardians[1]);
        wallet.supportRecovery();

        // create userOperation
        vm.startPrank(owners[0]);
        address sender = address(wallet);
        uint256 nonce = wallet.getNonce();
        bytes memory initCode = "";
        bytes memory callData = abi.encodeCall(MyWallet.executeRecovery, ());
        UserOperation memory userOp = createUserOperation(sender, nonce, initCode, callData);
        // sign 
        userOp.signature = signUserOp(userOp, ownerKeys[0]);
        vm.stopPrank();

        UserOperation[] memory ops;
        ops = new UserOperation[](1);
        ops[0] = userOp;

        // bundler send operation to entryPoint
        vm.prank(bundler);
        entryPoint.handleOps(ops, payable(bundler));

        // check effects
        assertTrue(wallet.isOwner(someone));
        assertFalse(wallet.isOwner(owners[2]));
        assertFalse(wallet.isRecovering());
        assertEq(wallet.recoverRound(), 1);
        (address addr1, address addr2, uint256 num) = wallet.getRecoveryInfo();
        assertEq(addr1, address(0));
        assertEq(addr2, address(0));
        assertEq(num, 0);
    }

    function testEntryFreezeWallet() public {
        // create userOperation
        vm.startPrank(owners[0]);
        address sender = address(wallet);
        uint256 nonce = wallet.getNonce();
        bytes memory initCode = "";
        bytes memory callData = abi.encodeCall(MyWallet.freezeWallet, ());
        UserOperation memory userOp = createUserOperation(sender, nonce, initCode, callData);
        // sign 
        userOp.signature = signUserOp(userOp, ownerKeys[0]);
        vm.stopPrank();

        UserOperation[] memory ops;
        ops = new UserOperation[](1);
        ops[0] = userOp;

        // bundler send operation to entryPoint
        vm.prank(bundler);
        entryPoint.handleOps(ops, payable(bundler));

        // check effects
        assertTrue(wallet.isFreezing());
    }

    function testEntryUnfreezeWallet() public {
        testEntryFreezeWallet();
        // create userOperation
        vm.startPrank(owners[0]);
        address sender = address(wallet);
        uint256 nonce = wallet.getNonce();
        bytes memory initCode = "";
        bytes memory callData = abi.encodeCall(MyWallet.unfreezeWallet, ());
        UserOperation memory userOp = createUserOperation(sender, nonce, initCode, callData);
        // sign 
        userOp.signature = signUserOp(userOp, ownerKeys[0]);
        vm.stopPrank();

        UserOperation[] memory ops;
        ops = new UserOperation[](1);
        ops[0] = userOp;

        // bundler send operation to entryPoint
        vm.prank(bundler);
        entryPoint.handleOps(ops, payable(bundler));

        assertTrue(wallet.unfreezeBy(0, owners[0]));
        assertEq(wallet.unfreezeCounter(), 1);
    }

    // utilities ====================================================
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
        uint256 _privatekey
    )
        internal
        view
        returns(bytes memory _signature)
    {
        bytes32 userOpHash = entryPoint.getUserOpHash(_userOp);
        bytes32 digest = userOpHash.toEthSignedMessageHash();
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(_privatekey, digest);
        _signature = abi.encodePacked(r, s, v); // note the order here is different from line above.
    }
}