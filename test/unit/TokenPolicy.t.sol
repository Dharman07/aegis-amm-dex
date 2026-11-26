pragma solidity ^0.8.30;

import {Test} from "forge-std/Test.sol";
import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import {IAccessControl} from "@openzeppelin/contracts/access/IAccessControl.sol";

import {TokenPolicy} from "../../src/security/TokenPolicy.sol";

contract PolicyMockERC20 is ERC20 {
    constructor() ERC20("Policy Token", "POL") {}
}

contract TokenPolicyTest is Test {
    TokenPolicy internal tokenPolicy;
    PolicyMockERC20 internal token;

    address internal unauthorizedUser = address(0x1234);
    address internal guardian = address(0x5678);

    function setUp() public {
        tokenPolicy = new TokenPolicy(address(this));

        token = new PolicyMockERC20();

        tokenPolicy.grantRole(tokenPolicy.TOKEN_GUARDIAN_ROLE(), guardian);
    }

    function testApproveToken() public {
        tokenPolicy.approveToken(address(token));

        assertEq(
            uint256(tokenPolicy.getTokenStatus(address(token))),
            uint256(TokenPolicy.TokenStatus.Approved)
        );

        assertTrue(tokenPolicy.isTokenAllowed(address(token)));
    }

    function testApproveZeroAddressReverts() public {
        vm.expectRevert(TokenPolicy.ZeroAddress.selector);

        tokenPolicy.approveToken(address(0));
    }

    function testApproveNonContractAddressReverts() public {
        vm.expectRevert(TokenPolicy.InvalidToken.selector);

        tokenPolicy.approveToken(unauthorizedUser);
    }

    function testApproveAlreadyApprovedTokenReverts() public {
        tokenPolicy.approveToken(address(token));

        vm.expectRevert(TokenPolicy.TokenAlreadyApproved.selector);

        tokenPolicy.approveToken(address(token));
    }

    function testRevokeToken() public {
        tokenPolicy.approveToken(address(token));

        tokenPolicy.revokeToken(address(token));

        assertFalse(tokenPolicy.isTokenAllowed(address(token)));

        assertEq(
            uint256(tokenPolicy.getTokenStatus(address(token))),
            uint256(TokenPolicy.TokenStatus.Unlisted)
        );
    }

    function testRevokedTokenCanBeApprovedAgain() public {
        tokenPolicy.approveToken(address(token));

        tokenPolicy.revokeToken(address(token));

        tokenPolicy.approveToken(address(token));

        assertTrue(tokenPolicy.isTokenAllowed(address(token)));
    }

    function testBlockToken() public {
        tokenPolicy.approveToken(address(token));

        vm.prank(guardian);
        tokenPolicy.blockToken(address(token));

        assertFalse(tokenPolicy.isTokenAllowed(address(token)));

        assertEq(
            uint256(tokenPolicy.getTokenStatus(address(token))),
            uint256(TokenPolicy.TokenStatus.Blocked)
        );
    }

    function testUnblockToken() public {
        tokenPolicy.approveToken(address(token));

        vm.prank(guardian);
        tokenPolicy.blockToken(address(token));

        tokenPolicy.unblockToken(address(token));

        assertTrue(tokenPolicy.isTokenAllowed(address(token)));
    }

    function testBlockedTokenCannotBeApprovedAgain() public {
        tokenPolicy.approveToken(address(token));

        vm.prank(guardian);
        tokenPolicy.blockToken(address(token));

        vm.expectRevert(TokenPolicy.TokenAlreadyBlocked.selector);

        tokenPolicy.approveToken(address(token));
    }

    function testUnapprovedTokenCannotBeBlocked() public {
        vm.prank(guardian);

        vm.expectRevert(TokenPolicy.TokenNotApproved.selector);

        tokenPolicy.blockToken(address(token));
    }

    function testUnapprovedTokenCannotBeRevoked() public {
        vm.expectRevert(TokenPolicy.TokenNotApproved.selector);

        tokenPolicy.revokeToken(address(token));
    }

    function testOnlyAdminCanApproveToken() public {
        vm.expectRevert(
            abi.encodeWithSelector(
                IAccessControl.AccessControlUnauthorizedAccount.selector,
                unauthorizedUser,
                tokenPolicy.TOKEN_ADMIN_ROLE()
            )
        );

        vm.prank(unauthorizedUser);
        tokenPolicy.approveToken(address(token));
    }

    function testOnlyGuardianCanBlockToken() public {
        tokenPolicy.approveToken(address(token));

        vm.expectRevert(
            abi.encodeWithSelector(
                IAccessControl.AccessControlUnauthorizedAccount.selector,
                unauthorizedUser,
                tokenPolicy.TOKEN_GUARDIAN_ROLE()
            )
        );

        vm.prank(unauthorizedUser);
        tokenPolicy.blockToken(address(token));
    }
}
