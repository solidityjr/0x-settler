// SPDX-License-Identifier: MIT
pragma solidity ^0.8.17;

import {BasePairTest} from "./BasePairTest.t.sol";
import {IUniswapV3Router} from "./vendor/IUniswapV3Router.sol";

abstract contract UniswapV3PairTest is BasePairTest {
    function uniswapV3Path() internal virtual returns (bytes memory);

    function testUniswapRouter() public {
        IUniswapV3Router UNISWAP_ROUTER = IUniswapV3Router(0xE592427A0AEce92De3Edee1F18E0157C05861564);

        vm.startPrank(FROM);
        deal(address(fromToken()), FROM, amount());
        fromToken().approve(address(UNISWAP_ROUTER), type(uint256).max);

        snapStartName("uniswapRouter_uniswapV3");
        UNISWAP_ROUTER.exactInput(
            IUniswapV3Router.ExactInputParams({
                path: uniswapV3Path(),
                recipient: FROM,
                deadline: block.timestamp + 1,
                amountIn: amount(),
                amountOutMinimum: 1
            })
        );
        snapEnd();
    }
}
