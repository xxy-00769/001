# M4-01 v0.1.1 — Web预览修复交付

2026-10-21，Asia/Shanghai。本轮仅修改Web实现、必要的测试/部署清单/文档，没有修改识别算法、UDP协议、FPGA、场景配置或网络配置。UNKNOWN仍显示未知。

## 实际部署与版本核对

SSH用户orangepi，端口22，实际HOME=/home/orangepi。修复前本地main.py、远端 `/home/orangepi/fpga_gs_m401_20261021/main.py` 与v0.1 manifest中的SHA256相同：

`dc1a27eae06c404c97948140917fb6abf5bb527cc3d3da9c8a51a405bf2ee07f`

新版本实际部署到 **`/home/orangepi/fpga_gs_m401_v0_1_1_20261021`**。旧v0.1目录完整保留，没有覆盖。CPU/Python3.10.12/OpenCV4.5.4/NumPy1.21.5，独立venv复用已有系统包，无新增依赖、sudo或自启。样例仅复制自旧目录已有的16秒FILE_TEST文件。

检查时无main.py在运行。本轮只运行自己的限时前台FILE_TEST和Web验证夹具，没有停止其他项目。测试结束后不留测试Web服务。本地v0.1原main.py、manifest、代码包和原文档在releases/v0.1/；原DELIVERY.md保留为v0.1历史报告。

## 修复内容

- main.py使用 `urlsplit(self.path).path` 匹配路由；首页、状态和图片接口均正确处理查询参数。
- 成功及错误响应统一设置 `Cache-Control: no-store, no-cache, must-revalidate, max-age=0`、`Pragma: no-cache`、`Expires: 0`，前端fetch也使用cache=no-store。
- 页面拆为简单preview.html，无前端依赖。获取并成功解码JPEG后才显示；未有图时显示等待首帧，HTTP错误/超时显示具体失败信息，隐藏破图并自动重试，恢复后无需手动刷新。
- 画面在上，模式/帧号/fps/灯态/边界/意图中文摘要在下；JSON默认折叠。图片与状态请求分别处理失败，4秒请求超时，每轮请求完成后500ms重试。
- deploy.ps1补上页面和本轮测试文件，部署检查仅运行test_web_preview，不重跑基线识别/模拟通信测试。

## 定向验证证据

香橙派执行 `.venv/bin/python -m unittest -v test_web_preview`：1项通过，0.531秒，覆盖无首帧503、错误响应禁止缓存、各路由查询参数、JPEG可解码和图片可用后的恢复。未重跑test_m401或simulate_peer。

浏览器经真实SSH转发访问板端。tabbit注册失效且没有可用交互浏览器连接，本轮未修浏览器安装；使用本机已有Edge的隔离无界面测试实例及已有Playwright执行实际页面JS，未安装新浏览器或依赖，未修改用户浏览器资料。保存的是网页截图，不是旧board_preview.jpg。

`evidence/v0.1.1/browser_report.json`、01～04截图：

1. 测试夹具先启动真实Handler、不提供图片，首页显示“等待首帧”，img隐藏、无破图、JSON折叠。
2. 启动同一App.file的真实录像FILE_TEST，首页不reload时帧号1→4、图片blob URL和解码像素内容均变化。
3. `/latest.jpg`、`/latest.jpg?t=arbitrary-123`、`/raw.jpg`、`/raw.jpg?t=raw`均HTTP200并由浏览器解码为1280×720；`/status.json`及查询参数版本正常200，均禁止缓存。
4. 在测试夹具暂停供帧并清空图片槽，实际图片接口返回503，页面显示明确错误、隐藏图片、自动重试；恢复实际文件供帧后无需刷新自动恢复。
5. 浏览器测试拦截状态请求后有明确失败提示；解除拦截后自动恢复。展开/折叠JSON正常，无页面JS异常。

夹具的平均fps包含人为首帧等待和暂停时间，不代表正常FILE_TEST速度。控制标记只在本轮专用测试目录存在，生产服务没有新增测试控制API。

随后用正式入口实际运行（70秒自动停止）：

```bash
cd /home/orangepi/fpga_gs_m401_v0_1_1_20261021
.venv/bin/python main.py --mode FILE_TEST --video 1021_file_test_16s.mp4 --scene scene.file_test.json --loop --output runs/web_production_v011 --web-port 8080 --duration 70
```

`evidence/v0.1.1/running_report.json`及05截图：浏览器经SSH18080→8080观察帧号43→69，processed=69、4.985fps、图片自然宽1280、JSON默认折叠，无JS异常。识别未知仍显示未知。本轮未重测识别准确率或完整性能基准。

## 启动、查看和停止

电脑PowerShell：

```powershell
ssh -t -p 22 -o HostKeyAlias=10.168.29.122 -o StrictHostKeyChecking=yes -L 18080:127.0.0.1:8080 orangepi@192.168.0.4
```

登录后在香橙派前台执行：

```bash
cd /home/orangepi/fpga_gs_m401_v0_1_1_20261021
.venv/bin/python main.py --mode FILE_TEST --video 1021_file_test_16s.mp4 --scene scene.file_test.json --loop --output runs/manual_web_v011 --web-port 8080
```

电脑打开 http://127.0.0.1:18080/ 。先看到等待首帧，随后上方录像和叠加持续刷新；下方显示中文模式、帧号、约5fps和实际识别结果。点击“展开诊断JSON”才出现完整数据。网页显示速度约2Hz，与5fps处理速度分别计。

停止：在运行Python的终端按Ctrl+C；执行exit关闭SSH转发。日志见runs/manual_web_v011/events.jsonl。

## 回退

先Ctrl+C停止v0.1.1，在同一登录终端运行旧版本：

```bash
cd /home/orangepi/fpga_gs_m401_20261021
.venv/bin/python main.py --mode FILE_TEST --video 1021_file_test_16s.mp4 --scene scene.file_test.json --loop --output runs/manual_file --web-port 8080
```

v0.1保留原Web缺陷，仅供完整版本回退；没有系统配置需要撤销，不使用pkill/killall。

## 回传指挥对话

```text
M4-01 v0.1.1已部署/home/orangepi/fpga_gs_m401_v0_1_1_20261021，修复前本地/远端v0.1 main.py SHA256一致，旧目录/home/orangepi/fpga_gs_m401_20261021完整保留。
修复urlsplit路由、禁止缓存、首帧等待/失败提示/自动重试；首页画面在上、中文摘要在下，JSON默认折叠。
板端定向Web测试通过；真实SSH转发浏览器确认JPEG带/不带查询参数均200且可解码、图片持续更新、首帧等待、503失败及状态请求失败后恢复。正式FILE_TEST测得4.985fps，无JS异常。
未重跑识别/模拟通信全套测试；算法、UDP、FPGA、网络配置不变，UNKNOWN未伪造。没有FPGA LIVE联调通过声明。
```
