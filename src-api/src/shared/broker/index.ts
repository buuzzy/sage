import { MockBrokerAdapter } from './mock-adapter';
import type { BrokerAdapter } from './types';

let adapter: BrokerAdapter | null = null;

export function getBrokerAdapter(): BrokerAdapter {
  if (!adapter) {
    // The public contract follows Futu OpenAPI semantics, while the initial
    // implementation uses deterministic mock data until the simulator account is ready.
    adapter = new MockBrokerAdapter();
  }
  return adapter;
}

export type {
  BrokerAccount,
  BrokerAdapter,
  BrokerEnvironment,
  BrokerMarket,
  BrokerPosition,
  KlinePoint,
  OrderType,
  SimulatedOrder,
  SubmitSimulatedOrderInput,
  TradeSide,
} from './types';
