/// 轻聊没有付费会员体系。
///
/// 原先按付费身份加锁的能力，对已登录用户一律开放。解开限制不会把账号
/// 标成会员，也不应绘制会员徽章。
abstract final class AccountCapabilities {
  static const bool unlocked = true;
}
