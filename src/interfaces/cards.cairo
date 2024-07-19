use starknet::ContractAddress;

#[starknet::interface]
trait ICardsImpl<TState> {
    fn claimCard(ref self: TState, minter: ContractAddress, tokenId: u256, amount: u256);
    fn setAllowedCaller(ref self: TState, contract: ContractAddress, allowed: bool);
}
