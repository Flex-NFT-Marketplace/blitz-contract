#[starknet::contract]
mod AtemuPoint {
    use atemu::interfaces::point::IPointPool;
    use starknet::{ContractAddress, get_tx_info, get_caller_address, get_block_timestamp};
    use pedersen::PedersenTrait;
    use hash::{HashStateTrait, HashStateExTrait};
    use openzeppelin::access::ownable::OwnableComponent;
    use openzeppelin::token::erc20::ERC20Component;
    use openzeppelin::security::{PausableComponent, ReentrancyGuardComponent};
    use openzeppelin::account::interface::{AccountABIDispatcher, AccountABIDispatcherTrait};
    use integer::BoundedInt;

    component!(path: OwnableComponent, storage: ownable, event: ownableEvent);
    component!(path: ReentrancyGuardComponent, storage: reentrancy, event: reentrancyEvent);
    component!(path: PausableComponent, storage: pausable, event: pausableEvent);

    #[abi(embed_v0)]
    impl OwnableImpl = OwnableComponent::OwnableImpl<ContractState>;

    #[abi(embed_v0)]
    impl PausableImpl = PausableComponent::PausableImpl<ContractState>;

    impl InternalOwnableImple = OwnableComponent::InternalImpl<ContractState>;

    impl InternalPausableImpl = PausableComponent::InternalImpl<ContractState>;

    impl InternalReentrancyImpl = ReentrancyGuardComponent::InternalImpl<ContractState>;

    const STARKNET_DOMAIN_TYPE_HASH: felt252 =
        selector!("StarkNetDomain(name:felt,version:felt,chainId:felt)");

    const POINT_POOL_STRUCT: felt252 =
        selector!(
            "SetterPoint(address:ContractAddress,point:u256,timestamp:u64)u256(low:felt,high:felt)"
        );

    const U256_TYPE_HASH: felt252 = selector!("u256(low:felt,high:felt)");

    #[storage]
    struct Storage {
        // address validating the proof
        validator: ContractAddress,
        // mapping user point (user address => point)
        userPoints: LegacyMap::<ContractAddress, u256>,
        // mapping bypass contracts give reward to user (contract address => isAllowed)
        bypassContract: LegacyMap::<ContractAddress, bool>,
        // mapping user proof (felt252 => isUsed)
        isUsedProof: LegacyMap::<felt252, bool>,
        allowances: LegacyMap<(ContractAddress, ContractAddress), u256>,
        #[substorage(v0)]
        ownable: OwnableComponent::Storage,
        #[substorage(v0)]
        reentrancy: ReentrancyGuardComponent::Storage,
        #[substorage(v0)]
        pausable: PausableComponent::Storage,
    }

    #[derive(Drop, Copy, Hash)]
    struct SetterPoint {
        address: ContractAddress,
        point: u256,
        timestamp: u64,
    }

    #[derive(Drop, Copy, Hash)]
    struct StarknetDomain {
        name: felt252,
        version: felt252,
        chain_id: felt252,
    }

    #[event]
    #[derive(Drop, starknet::Event)]
    enum Event {
        AddPoint: AddPoint,
        TransferPoint: TransferPoint,
        #[flat]
        ownableEvent: OwnableComponent::Event,
        #[flat]
        reentrancyEvent: ReentrancyGuardComponent::Event,
        #[flat]
        pausableEvent: PausableComponent::Event,
    }

    #[derive(Drop, starknet::Event)]
    struct AddPoint {
        #[key]
        user: ContractAddress,
        point: u256,
        timestamp: u64
    }

    #[derive(Drop, PartialEq, starknet::Event)]
    struct TransferPoint {
        #[key]
        from: ContractAddress,
        #[key]
        to: ContractAddress,
        value: u256
    }

    #[constructor]
    fn constructor(ref self: ContractState, owner: ContractAddress, validator: ContractAddress) {
        self.ownable.initializer(owner);
        self.validator.write(validator);
    }

    #[abi(embed_v0)]
    impl PointImpl of IPointPool<ContractState> {
        fn addPoint(
            ref self: ContractState,
            receiver: ContractAddress,
            amount: u256,
            timestamp: u64,
            proof: Array<felt252>
        ) {
            self.pausable.assert_not_paused();
            self.reentrancy.start();
            let msgHash = self.get_message_hash(receiver, amount, timestamp, self.getValidator());
            assert(!self.isUsedProof.read(msgHash), 'ATEMU: PROOF IS USED');
            assert(
                self.is_valid_signature(self.validator.read(), msgHash, proof) == 'VALID',
                'ATEMU: INVALID SIGNATURE'
            );

            self.isUsedProof.write(msgHash, true);

            let mut point = self.userPoints.read(receiver);
            point += amount;
            self.userPoints.write(receiver, point);

            self.emit(AddPoint { user: receiver, point: amount, timestamp });

            self.reentrancy.end();
        }

        fn addPointFromOtherContract(
            ref self: ContractState, receiver: ContractAddress, amount: u256
        ) {
            self.pausable.assert_not_paused();
            self.reentrancy.start();
            assert(self.bypassContract.read(get_caller_address()), 'ATEMU: CALLER NOT ALLOWED');

            let mut point = self.userPoints.read(receiver);
            point += amount;
            self.userPoints.write(receiver, point);

            self.emit(AddPoint { user: receiver, point: amount, timestamp: get_block_timestamp() });

            self.reentrancy.end();
        }

        fn setPermission(ref self: ContractState, address: ContractAddress, isAllowed: bool) {
            self.ownable.assert_only_owner();
            self.bypassContract.write(address, isAllowed)
        }

        fn setValidator(ref self: ContractState, newValidator: ContractAddress) {
            self.ownable.assert_only_owner();
            self.validator.write(newValidator)
        }

        fn transfer(ref self: ContractState, recipient: ContractAddress, amount: u256) {
            let sender = get_caller_address();
            self._transfer(sender, recipient, amount);
        }

        fn transferFrom(
            ref self: ContractState,
            sender: ContractAddress,
            recipient: ContractAddress,
            amount: u256
        ) {
            let caller = get_caller_address();
            self._spend_allowance(sender, caller, amount);
            self._transfer(sender, recipient, amount);
        }

        fn approve(ref self: ContractState, spender: ContractAddress, amount: u256) {
            let caller = get_caller_address();
            self._approve(caller, spender, amount);
        }
        fn allowance(
            ref self: ContractState, owner: ContractAddress, spender: ContractAddress
        ) -> u256 {
            self.allowances.read((owner, spender))
        }

        fn getUserPoint(self: @ContractState, address: ContractAddress) -> u256 {
            self.userPoints.read(address)
        }
        fn getValidator(self: @ContractState) -> ContractAddress {
            self.validator.read()
        }
    }

    trait IStructHash<T> {
        fn hash_struct(self: @T) -> felt252;
    }

    impl StructHashStarknetDomain of IStructHash<StarknetDomain> {
        fn hash_struct(self: @StarknetDomain) -> felt252 {
            let mut state = PedersenTrait::new(0);
            state = state.update_with(STARKNET_DOMAIN_TYPE_HASH);
            state = state.update_with(*self);
            state = state.update_with(4);
            state.finalize()
        }
    }

    impl StructHashSetterPoint of IStructHash<SetterPoint> {
        fn hash_struct(self: @SetterPoint) -> felt252 {
            let mut state = PedersenTrait::new(0);
            state = state.update_with(POINT_POOL_STRUCT);
            state = state.update_with(*self.address);
            state = state.update_with(self.point.hash_struct());
            state = state.update_with(*self.timestamp);
            state = state.update_with(4);
            state.finalize()
        }
    }

    impl StructHashU256 of IStructHash<u256> {
        fn hash_struct(self: @u256) -> felt252 {
            let mut state = PedersenTrait::new(0);
            state = state.update_with(U256_TYPE_HASH);
            state = state.update_with(*self);
            state = state.update_with(3);
            state.finalize()
        }
    }

    #[abi(per_item)]
    #[generate_trait]
    impl ValidateSignature of IValidateSignature {
        #[external(v0)]
        fn pause(ref self: ContractState) {
            self.ownable.assert_only_owner();
            self.pausable._pause();
        }

        #[external(v0)]
        fn unpause(ref self: ContractState) {
            self.ownable.assert_only_owner();
            self.pausable._unpause();
        }

        fn is_valid_signature(
            self: @ContractState, signer: ContractAddress, hash: felt252, signature: Array<felt252>
        ) -> felt252 {
            let account: AccountABIDispatcher = AccountABIDispatcher { contract_address: signer };
            account.is_valid_signature(hash, signature)
        }

        fn get_message_hash(
            self: @ContractState,
            receiver: ContractAddress,
            point: u256,
            timestamp: u64,
            signer: ContractAddress
        ) -> felt252 {
            let domain = StarknetDomain {
                name: 'poolpoint', version: 1, chain_id: get_tx_info().unbox().chain_id
            };
            let mut state = PedersenTrait::new(0);
            state = state.update_with('StarkNet Message');
            state = state.update_with(domain.hash_struct());
            state = state.update_with(signer);
            let setterPoint = SetterPoint { address: receiver, point, timestamp };
            state = state.update_with(setterPoint.hash_struct());
            // Hashing with the amount of elements being hashed 
            state = state.update_with(4);
            state.finalize()
        }

        fn _transfer(
            ref self: ContractState,
            sender: ContractAddress,
            recipient: ContractAddress,
            amount: u256
        ) {
            assert(!sender.is_zero(), 'approve from 0');
            assert(!recipient.is_zero(), 'approve to 0');
            self._update(sender, recipient, amount);
        }

        fn _update(
            ref self: ContractState, from: ContractAddress, to: ContractAddress, amount: u256
        ) {
            let zero_address = Zeroable::zero();
            if (from != zero_address) {
                let from_balance = self.userPoints.read(from);
                assert(from_balance >= amount, 'insufficient balance');
                self.userPoints.write(from, from_balance - amount);
            }

            if (to != zero_address) {
                let to_balance = self.userPoints.read(to);
                self.userPoints.write(to, to_balance + amount);
            }

            self.emit(TransferPoint { from, to, value: amount });
        }

        fn _spend_allowance(
            ref self: ContractState, owner: ContractAddress, spender: ContractAddress, amount: u256
        ) {
            let current_allowance = self.allowances.read((owner, spender));
            if current_allowance != BoundedInt::max() {
                assert(current_allowance >= amount, 'insufficient allowance');
                self._approve(owner, spender, current_allowance - amount);
            }
        }

        fn _approve(
            ref self: ContractState, owner: ContractAddress, spender: ContractAddress, amount: u256
        ) {
            assert(!owner.is_zero(), 'approve from 0');
            assert(!spender.is_zero(), 'approve to 0');
            self.allowances.write((owner, spender), amount);
        }
    }
}
