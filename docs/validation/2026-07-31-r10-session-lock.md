# r10 U25S 会话锁验证（2026-07-31）

## r9 构建与正式升级

- GitHub Actions run：`30617784653`
- source commit：`64e813c90f843ea4a46c154ce9da2832f9254a08`
- OpenWrt 25.12.5 APK 与 24.10.7 IPK 的真实 SDK 构建均通过。
- 汇总制品 `SHA256SUMS` 全部通过。
- r9 APK SHA-256：
  `8087b9eeadea5b80f56a42245d773ac1c9af0a9b725ecbb15275eae028057678`
- Cudy TR3000 上正式升级结果：
  `0.1.0_rc1-r8 -> 0.1.0_rc1-r9`

安装后验证：

- 守护进程正在运行；
- LuCI 显示设备在线、后端正常、NR5G-SA、`eth2` 已连接；
- 管理密码入口存在，并显示凭据已保存；
- `write_enabled=0`；
- power backend 为 `unconfigured`；
- power calibrated 为 `0`；
- battery policy 为禁用；
- 凭据文件仍为 root 所有、模式 `0600`；
- 临时安装文件、HTTP 诊断文件和一次性 SSH 公钥均已清理；
- 原 crontab 三行保持不变，`/etc/rc.local` 已恢复。

## 新发现

r9 安装后严格只执行了一次：

```sh
/usr/libexec/zte-u25s-sim-calibrate probe
```

结果为稳定、无敏感信息的：

```json
{"ok":false,"mode":"probe","code":"authentication_failed"}
```

同一时刻，procd 守护进程通过相同的 `session.sh` 持续读取设备成功，LuCI 快照也
刷新为正常状态。因此密码文件形态和 r9 摘要算法已不再是最强嫌疑。结合目标固件
使用全局 `LD` 挑战，当前证据更符合校准 probe 与 30 秒轮询在
`GET LD -> POST LOGIN` 窗口内发生跨进程争用。这是基于实机现象与代码路径的推断，
必须由 r10 的协调后实机 probe 最终验证。

## r10 修复

会话层为完整 `LD -> LOGIN` 交换增加共享进程锁，覆盖守护进程、校准工具和动作
执行器，而不是只给 probe 增加特殊分支。锁位于稳定存在的 `/var/run`，不依赖
守护进程先创建自己的运行目录。持有者先写好 PID 临时文件，再用同文件系统硬
链接原子发布锁，避免“建目录后尚未写 PID”或“删 PID 后尚未删目录”的永久空锁
窗口。锁具备以下行为：

- 活跃进程持锁时其他登录等待后失败，不抢占挑战；
- 持锁进程正常返回或收到信号时释放锁；
- PID 已不存在的异常残留锁也失败关闭，避免并发回收者误删新锁；设备重启后
  `/var/run` 自动清空；
- 自定义锁父目录不存在时失败关闭，不创建权限不明的目录；
- 锁只包围登录交换，不包围设备状态读取或写动作。

TDD 红灯证据：生产代码尚未加锁时，HTTP stub 要求登录期间持锁，
`test_session` 失败 2 项。

实现后：

- `test_session`：48 assertions PASS，包含两个真实 shell 进程的顺序验证、活锁超时、两个并发进程
  面对死 PID 锁时均失败关闭、父目录缺失和 TERM 清理；
- `test_u25s_simulator`：56 assertions PASS；
- `test_sim_calibration`：413 assertions PASS；
- `make lint`：PASS。

## r10 构建、部署和实机结论

- GitHub Actions run：`30620735690`
- source commit：`44570470986d7e22ecb3fe6b47b73f114d703a14`
- OpenWrt 25.12.5 APK 与 24.10.7 IPK 的真实 SDK 构建均通过。
- r10 APK SHA-256：
  `9ec3403a417747c0e77786486305e9854f73285ee4bf518614cad6d3c3d39f5b`
- r10 IPK SHA-256：
  `a1c64a2a96a0f9bb6952f88f6a1f2f12f9a6212f4695069e7f84887676a05718`
- Cudy TR3000 上正式升级结果：
  `0.1.0_rc1-r9 -> 0.1.0_rc1-r10`

安装后严格只执行了一次只读 probe，仍返回：

```json
{"ok":false,"mode":"probe","code":"authentication_failed"}
```

因此“全局 `LD` 挑战并发导致认证失败”的根因假设已被实机证伪。会话锁本身仍是
必要的并发正确性修复，但不是这次认证失败的充分修复。安装后守护进程正常运行，
会话锁无残留，凭据文件保持 root 所有和 `0600`，临时 SSH 授权与安装文件均已
清理。SIM 切换仍只能在备用 U25S 上执行。
