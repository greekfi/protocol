// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import { Test, console } from "forge-std/Test.sol";

contract ErrorContract {
    error CustomError();
    error CustomErrorWithParam(uint256 value);

    function revertWithString() public pure {
        require(false, "This is a string error message");
    }

    function revertWithShortString() public pure {
        require(false, "Error");
    }

    function revertWithLongString() public pure {
        require(false, "Fee-on-transfer tokens not supported");
    }

    function revertWithCustomError() public pure {
        revert CustomError();
    }

    function revertWithCustomErrorParam() public pure {
        revert CustomErrorWithParam(123);
    }

    function revertWithPlainRevert() public pure {
        revert();
    }
}

contract GasErrorsTest is Test {
    ErrorContract errorContract;

    function setUp() public {
        errorContract = new ErrorContract();
    }

    function test_StringError() public {
        try errorContract.revertWithString() {
            fail();
        } catch {
            // Expected to revert
        }
    }

    function test_ShortStringError() public {
        try errorContract.revertWithShortString() {
            fail();
        } catch {
            // Expected to revert
        }
    }

    function test_LongStringError() public {
        try errorContract.revertWithLongString() {
            fail();
        } catch {
            // Expected to revert
        }
    }

    function test_CustomError() public {
        try errorContract.revertWithCustomError() {
            fail();
        } catch {
            // Expected to revert
        }
    }

    function test_CustomErrorWithParam() public {
        try errorContract.revertWithCustomErrorParam() {
            fail();
        } catch {
            // Expected to revert
        }
    }

    function test_PlainRevert() public {
        try errorContract.revertWithPlainRevert() {
            fail();
        } catch {
            // Expected to revert
        }
    }
}
