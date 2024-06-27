use starknet::ContractAddress;

#[starknet::interface]
trait IPointPool<TState> {
    fn addPoint(
        ref self: TState,
        receiver: ContractAddress,
        amount: u256,
        timestamp: u64,
        proof: Array<felt252>
    );
    fn addPointFromOtherContract(ref self: TState, receiver: ContractAddress, amount: u256);
    fn setPermission(ref self: TState, address: ContractAddress, isAllowed: bool);
    fn setValidator(ref self: TState, newValidator: ContractAddress);
    fn transfer(ref self: TState, recipient: ContractAddress, amount: u256);
    fn transferFrom(
        ref self: TState, sender: ContractAddress, recipient: ContractAddress, amount: u256
    );
    fn approve(ref self: TState, spender: ContractAddress, amount: u256);
    fn allowance(ref self: TState, owner: ContractAddress, spender: ContractAddress) -> u256;
    fn getUserPoint(self: @TState, address: ContractAddress) -> u256;
    fn getValidator(self: @TState) -> ContractAddress;
}
