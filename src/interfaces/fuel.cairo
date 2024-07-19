use starknet::ContractAddress;

#[starknet::interface]
trait IFuel<TState> {
    fn manuallyCreatePool(ref self: TState);
    fn joiningPool(ref self: TState, poolId: u256, amountPoint: u256);
    fn cancelPool(ref self: TState, poolId: u256);
    fn updateDuration(ref self: TState, duration: u64);
    fn updatePoolPointAddress(ref self: TState, pointAddress: ContractAddress);
    fn updateCardAddress(ref self: TState, cardAddress: ContractAddress);
    fn updateDrawer(ref self: TState, drawer: ContractAddress);
    fn claimReward(
        ref self: TState, poolId: u256, cardId: u256, amountCards: u256, proof: Array::<felt252>
    );
}
