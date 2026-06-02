/** westock 行情不可用（未配置 key、接口失败或无数据）时抛出，API 层映射为 503。 */
export class MarketDataUnavailableError extends Error {
  constructor(message: string) {
    super(message);
    this.name = 'MarketDataUnavailableError';
  }
}
