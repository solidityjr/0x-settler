// SPDX-License-Identifier: MIT
pragma solidity ^0.8.25;

import {IERC20} from "forge-std/interfaces/IERC20.sol";
import {ISignatureTransfer} from "permit2/src/interfaces/ISignatureTransfer.sol";

import {UniswapV4} from "src/core/UniswapV4.sol";
import {POOL_MANAGER, IUnlockCallback} from "src/core/UniswapV4Types.sol";
import {IPoolManager} from "uniswapv4/interfaces/IPoolManager.sol";

import {SignatureExpired} from "src/core/SettlerErrors.sol";
import {Panic} from "src/utils/Panic.sol";

import {Test} from "forge-std/Test.sol";

import {console} from "forge-std/console.sol";

contract UniswapV4Dummy is UniswapV4 {
    address private immutable _deployer;

    constructor() {
        _deployer = msg.sender;
    }

    function _msgSender() internal view override returns (address) {
        return _deployer;
    }

    function _isForwarded() internal pure override returns (bool) {
        return false;
    }

    function _msgData() internal pure override returns (bytes calldata) {
        return msg.data;
    }

    function _hasMetaTxn() internal pure override returns (bool) {
        return false;
    }

    function _dispatch(uint256 i, bytes4 action, bytes calldata data) internal override returns (bool) {
        revert("unimplemented"); // TODO:
    }

    function _isRestrictedTarget(address) internal pure override returns (bool) {
        revert("unimplemented");
    }

    function _operator() internal view override returns (address) {
        return msg.sender;
    }

    function _permitToSellAmountCalldata(ISignatureTransfer.PermitTransferFrom calldata permit)
        internal
        pure
        override
        returns (uint256)
    {
        return permit.permitted.amount;
    }

    function _permitToSellAmount(ISignatureTransfer.PermitTransferFrom memory)
        internal
        pure
        override
        returns (uint256)
    {
        revert("unimplemented");
    }

    function _permitToTransferDetails(ISignatureTransfer.PermitTransferFrom memory permit, address recipient)
        internal
        view
        override
        returns (ISignatureTransfer.SignatureTransferDetails memory transferDetails, uint256 sellAmount)
    {
        transferDetails.to = recipient;
        transferDetails.requestedAmount = sellAmount = _permitToSellAmount(permit);
    }

    function _transferFromIKnowWhatImDoing(
        ISignatureTransfer.PermitTransferFrom memory permit,
        ISignatureTransfer.SignatureTransferDetails memory transferDetails,
        address from,
        bytes32 witness,
        string memory witnessTypeString,
        bytes memory sig,
        bool isForwarded
    ) internal override {
        revert("unimplemented");
    }

    function _transferFromIKnowWhatImDoing(
        ISignatureTransfer.PermitTransferFrom memory permit,
        ISignatureTransfer.SignatureTransferDetails memory transferDetails,
        address from,
        bytes32 witness,
        string memory witnessTypeString,
        bytes memory sig
    ) internal override {
        return _transferFromIKnowWhatImDoing(
            permit, transferDetails, from, witness, witnessTypeString, sig, _isForwarded()
        );
    }

    function _transferFrom(
        ISignatureTransfer.PermitTransferFrom memory permit,
        ISignatureTransfer.SignatureTransferDetails memory transferDetails,
        bytes memory sig,
        bool isForwarded
    ) internal override {
        assert(!isForwarded);
        if (transferDetails.requestedAmount > permit.permitted.amount) {
            Panic.panic(Panic.ARITHMETIC_OVERFLOW);
        }
        if (permit.deadline < block.timestamp) {
            revert SignatureExpired(permit.deadline);
        }
        assert(permit.nonce == 0);
        IERC20(permit.permitted.token).transferFrom(_msgSender(), transferDetails.to, transferDetails.requestedAmount);
    }

    function _transferFrom(
        ISignatureTransfer.PermitTransferFrom memory permit,
        ISignatureTransfer.SignatureTransferDetails memory transferDetails,
        bytes memory sig
    ) internal override {
        return _transferFrom(permit, transferDetails, sig, _isForwarded());
    }

    function _setOperatorAndCall(
        address target,
        bytes memory data,
        uint32 selector,
        function (bytes calldata) internal returns (bytes memory) callback
    ) internal override returns (bytes memory) {
        revert("unimplemented"); // TODO:
    }

    modifier metaTx(address msgSender, bytes32 witness) override {
        revert("unimplemented");
        _;
    }

    modifier takerSubmitted() override {
        revert("unimplemented");
        _;
    }

    function _allowanceHolderTransferFrom(address, address, address, uint256) internal pure override {
        revert("unimplemented");
    }
}

contract UniswapV4UnitTest is Test, IUnlockCallback {
    function unlockCallback(bytes calldata) external view override returns (bytes memory) {
        assert(msg.sender == address(POOL_MANAGER));
        return unicode"Hello, World!";
    }

    function _replaceAll(bytes memory haystack, bytes32 needle, bytes32 replace, bytes32 mask)
        internal
        view
        returns (uint256 count)
    {
        assembly ("memory-safe") {
            let padding
            for {
                let x := and(mask, sub(0x00, mask))
                let i := 0x07
            } gt(i, 0x02) { i := sub(i, 0x01) } {
                let s := shl(i, 0x01) // [128, 64, 32, 16, 8]
                if shr(s, shr(padding, x)) { padding := add(s, padding) }
            }

            padding := add(0x01, shr(0x03, padding))
            needle := and(mask, needle)
            replace := and(mask, replace)

            for {
                let i := add(0x20, haystack)
                let end := add(padding, add(mload(haystack), haystack))
            } lt(i, end) { i := add(0x01, i) } {
                let word := mload(i)
                if eq(and(mask, word), needle) {
                    mstore(i, or(and(not(mask), word), replace))
                    count := add(0x01, count)
                }
            }
        }
    }

    function _deployPoolManager() internal {
        bytes memory poolManagerCode = vm.getCode("PoolManager.sol:PoolManager");
        address poolManagerSrc;
        assembly ("memory-safe") {
            poolManagerSrc := create(0x00, add(0x20, poolManagerCode), mload(poolManagerCode))
        }
        require(poolManagerSrc != address(0));
        poolManagerCode = poolManagerSrc.code;
        uint256 replaceCount = _replaceAll(
            poolManagerCode,
            bytes32(bytes20(uint160(poolManagerSrc))),
            bytes32(bytes20(uint160(address(POOL_MANAGER)))),
            bytes32(bytes20(type(uint160).max))
        );
        console.log("replaced", replaceCount, "occurrences of pool manager immutable address");
        vm.etch(address(POOL_MANAGER), poolManagerCode);

        vm.record();
        (bool success, bytes memory returndata) = address(POOL_MANAGER).staticcall(abi.encodeWithSignature("owner()"));
        assert(abi.decode(returndata, (address)) == address(0));
        (bytes32[] memory readSlots,) = vm.accesses(address(POOL_MANAGER));
        assert(readSlots.length == 1);
        bytes32 ownerSlot = readSlots[0];
        assert(vm.load(address(POOL_MANAGER), ownerSlot) == bytes32(0));
        vm.store(address(POOL_MANAGER), ownerSlot, bytes32(uint256(uint160(address(this)))));
    }

    function setUp() public {
        _deployPoolManager();
    }

    function testNothing() public {
        assertEq(
            keccak256(POOL_MANAGER.unlock(new bytes(0))),
            0xacaf3289d7b601cbd114fb36c4d29c85bbfd5e133f14cb355c3fd8d99367964f
        );
    }
}
