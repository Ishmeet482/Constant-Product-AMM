#!/usr/bin/env node

const readline = require('readline');

const BPS_DENOMINATOR = 10000;

class Pool {
  constructor(id, tokenA, tokenB, feeBps, reserveA, reserveB) {
    this.id = id;
    this.tokenA = tokenA;
    this.tokenB = tokenB;
    this.feeBps = feeBps;
    this.reserveA = reserveA;
    this.reserveB = reserveB;
  }
}

const pools = [];

function createPool(tokenA, tokenB, feeBps, reserveA, reserveB) {
  const id = pools.length + 1;
  const pool = new Pool(id, tokenA, tokenB, feeBps, reserveA, reserveB);
  pools.push(pool);
  return pool;
}

function getAmountOut(pool, amountIn, aToB) {
  if (amountIn <= 0) return { amountOut: 0, fee: 0 };
  const reserveIn = aToB ? pool.reserveA : pool.reserveB;
  const reserveOut = aToB ? pool.reserveB : pool.reserveA;
  if (reserveIn <= 0 || reserveOut <= 0) return { amountOut: 0, fee: 0 };

  const fee = Math.floor((amountIn * pool.feeBps) / BPS_DENOMINATOR);
  const amountInAfterFee = amountIn - fee;
  const numerator = amountInAfterFee * reserveOut;
  const denominator = reserveIn + amountInAfterFee;
  const amountOut = Math.floor(numerator / denominator);
  return { amountOut, fee };
}

function swap(pool, amountIn, aToB) {
  const { amountOut, fee } = getAmountOut(pool, amountIn, aToB);
  if (amountOut <= 0) return { amountOut, fee };

  if (aToB) {
    pool.reserveA += amountIn;
    pool.reserveB -= amountOut;
  } else {
    pool.reserveB += amountIn;
    pool.reserveA -= amountOut;
  }
  return { amountOut, fee };
}

function listPools() {
  if (pools.length === 0) {
    console.log('\nNo pools created yet.');
    return;
  }
  console.log('\nExisting pools:');
  for (const p of pools) {
    console.log(`  [${p.id}] ${p.tokenA}/${p.tokenB} | fee=${p.feeBps}bps | reserves=${p.reserveA}/${p.reserveB}`);
  }
}

const rl = readline.createInterface({
  input: process.stdin,
  output: process.stdout
});

function ask(question) {
  return new Promise(resolve => rl.question(question, resolve));
}

async function mainMenu() {
  while (true) {
    console.log('\n=== Sui AMM Demo CLI ===');
    console.log('1) Create pool');
    console.log('2) List pools');
    console.log('3) Swap');
    console.log('4) Exit');
    const choice = (await ask('Select an option: ')).trim();

    if (choice === '1') {
      const tokenA = (await ask('Token A symbol: ')).trim() || 'TKA';
      const tokenB = (await ask('Token B symbol: ')).trim() || 'TKB';
      const feeStr = (await ask('Fee bps (e.g. 5, 30, 100): ')).trim() || '30';
      const feeBps = parseInt(feeStr, 10) || 30;
      const resAStr = (await ask('Initial reserve A: ')).trim() || '1000000';
      const resBStr = (await ask('Initial reserve B: ')).trim() || '1000000';
      const reserveA = parseInt(resAStr, 10) || 1000000;
      const reserveB = parseInt(resBStr, 10) || 1000000;
      const pool = createPool(tokenA, tokenB, feeBps, reserveA, reserveB);
      console.log(`Created pool [${pool.id}] ${pool.tokenA}/${pool.tokenB}.`);
    } else if (choice === '2') {
      listPools();
    } else if (choice === '3') {
      if (pools.length === 0) {
        console.log('No pools available. Create one first.');
        continue;
      }
      listPools();
      const idStr = (await ask('Pool id: ')).trim();
      const id = parseInt(idStr, 10);
      const pool = pools.find(p => p.id === id);
      if (!pool) {
        console.log('Invalid pool id.');
        continue;
      }
      console.log(`Selected pool [${pool.id}] ${pool.tokenA}/${pool.tokenB}`);
      const dir = (await ask(`Direction (1 = ${pool.tokenA}->${pool.tokenB}, 2 = ${pool.tokenB}->${pool.tokenA}): `)).trim();
      const aToB = dir !== '2';
      const amountStr = (await ask('Amount in: ')).trim();
      const amountIn = parseInt(amountStr, 10);
      if (!Number.isFinite(amountIn) || amountIn <= 0) {
        console.log('Invalid amount.');
        continue;
      }
      const { amountOut, fee } = getAmountOut(pool, amountIn, aToB);
      console.log(`Quote: output=${amountOut}, fee=${fee}`);
      const confirm = (await ask('Execute swap? (y/n): ')).trim().toLowerCase();
      if (confirm === 'y') {
        const res = swap(pool, amountIn, aToB);
        console.log(`Executed swap. Received=${res.amountOut}, fee=${res.fee}`);
        console.log(`New reserves: ${pool.reserveA}/${pool.reserveB}`);
      }
    } else if (choice === '4') {
      break;
    } else {
      console.log('Invalid option.');
    }
  }
  rl.close();
}

mainMenu().catch(err => {
  console.error('Error in CLI:', err);
  rl.close();
});
