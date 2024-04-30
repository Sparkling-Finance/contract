module flask::flask{
    use sui::coin::{Self, Coin, TreasuryCap};
    use sui::balance::{Self, Balance, Supply};

    use flask::utils;
    use flask::event;
    
    const ERR_WRONG_VERSION: u64 = 1;
    const ERR_ZERO_VALUE: u64 = 101;
    const ERR_INSUFFICIENT_DEPOSIT: u64 = 102;
    const ERR_ZERO_SUPPLY: u64 = 103;
    const ERR_PENDING_REWARDS: u64 = 104;

    const VERSIOIN: u64 = 1;

    public struct Flask<phantom R, phantom S> has key{
        id: UID,
        version: u64,
        reserves: Balance<R>,
        supply: Supply<S>
    }

    fun assert_pacakge_version<R, S>(self: &Flask<R, S>){
        assert!(self.version == VERSIOIN, ERR_WRONG_VERSION);
    }

    // === Getter ===
    public fun reserves<R, S>(self: &Flask<R, S>):u64{
        balance::value(&self.reserves)
    }
    public fun supply<R, S>(self: &Flask<R, S>):u64{
        balance::supply_value(&self.supply)
    }
    public fun reserves_to_supply<R, S>(self: &Flask<R, S>):u64{
        reserves(self) / supply(self)
    }
    public fun claimable<R, S>(
        self: &Flask<R, S>,
        shares: u64
    ):u64
    {
        if(shares > reserves(self)) return 0;
        utils::mul_div(shares, reserves(self), supply(self))
    }

    // consume treasury cap to create Supply
    entry public fun initialize<R, S>(
        treasury_cap: TreasuryCap<S>,
        ctx: &mut TxContext
    ){
        assert!(coin::total_supply(&treasury_cap) == 0, ERR_ZERO_SUPPLY);
        let flask = Flask<R, S>{
            id: object::new(ctx),
            version: VERSIOIN,
            reserves: balance::zero<R>(),
            supply: coin::treasury_into_supply(treasury_cap)
        };

        transfer::share_object(flask);
    }

    public fun collect_rewards<R, S>(
        self: &mut Flask<R, S>,
        rewards: Balance<R>
    ){
        assert_pacakge_version(self);
        assert!(reserves(self) != 0 && supply(self) != 0, ERR_PENDING_REWARDS);
        let rewards_val = balance::value(&rewards);
        
        balance::join(&mut self.reserves, rewards);

        event::collect_rewards(rewards_val);
    }

    public fun deposit<R, S>(
        self: &mut Flask<R, S>,
        deposit: Coin<R>
    ):Balance<S>{
        assert_pacakge_version(self);
        let deposit_val = coin::value(&deposit);
        assert!(deposit_val > 0, ERR_ZERO_VALUE);
        
        let supply = supply(self);
        let minted_sbuck_val= if(supply == 0){
            deposit_val
        }else{
            utils::mul_div(deposit_val, supply(self), reserves(self))
        };

        assert!(minted_sbuck_val > 0, ERR_INSUFFICIENT_DEPOSIT);

        coin::put(&mut self.reserves, deposit);
        let sbuck_bal = balance::increase_supply(&mut self.supply, minted_sbuck_val);
        event::deposit(deposit_val, balance::value(&sbuck_bal));

        sbuck_bal
    }

    public fun withdraw<R, S>(
        self: &mut Flask<R, S>,
        shares: Coin<S>
    ):Balance<R>{
        let shares_val = coin::value(&shares);
        assert!(shares_val > 0, ERR_ZERO_VALUE);

        // calculate claimed rewards
        let claimable = utils::mul_div(shares_val, reserves(self), supply(self));
        let sbuck_val = balance::decrease_supply(&mut self.supply, coin::into_balance(shares));

        let claimed_buck = balance::split(&mut self.reserves, claimable);

        event::burn(sbuck_val, balance::value(&claimed_buck));
        
        claimed_buck
    }
}
