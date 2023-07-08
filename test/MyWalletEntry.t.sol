// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.17;

import { TestHelper } from "./Helper/TestHelper.t.sol";
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
        uint256 nonce = entryPoint.getNonce(address(wallet), 0);
        bytes memory initCode = "";
        bytes memory callData = abi.encodeCall(MyWallet.entryPointTestFunction, ());
        UserOperation memory userOp = createUserOperation(sender, nonce, initCode, callData);
        // sign 
        userOp.signature = signUserOp(userOp, ownerKeys[0]);
        vm.stopPrank();

        // bundler simulate Operation
        // Successful result is ValidationResult error.
        vm.startPrank(bundler);
        vm.expectRevert();
        entryPoint.simulateValidation(userOp); // should be done offchain
        // "ValidationResult((62582, 7100000000000000, false, 0, 281474976710655, 0x), (0, 0), (0, 0), (0, 0))"
        vm.stopPrank();
    }

    function testEntryHandleOp() public {
        assertEq(address(wallet).balance, 0);
        uint256 balanceBefore = bundler.balance;

        // create userOperation
        vm.startPrank(owners[0]);
        address sender = address(wallet);
        uint256 nonce = 0;
        bytes memory initCode = "";
        bytes memory callData = abi.encodeCall(MyWallet.entryPointTestFunction, ());
        UserOperation memory userOp = createUserOperation(sender, nonce, initCode, callData);
        // sign 
        userOp.signature = signUserOp(userOp, ownerKeys[0]);
        vm.stopPrank();

        // bundler send operation to entryPoint
        UserOperation[] memory ops;
        ops = new UserOperation[](1);
        ops[0] = userOp;
        vm.prank(bundler);
        entryPoint.handleOps(ops, payable(bundler));
        
        // bundler got compensate payment
        assertGt(bundler.balance, balanceBefore);
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