# XGO RaspberryPi-CM4 项目总览

![XGO 机器人外观](../RaspberryPi-CM4-main/pics/luwu@3x.png)

## 1. 系统概况

- **硬件平台：** 树莓派 CM4、XGO 四足机器人（含 12 自由度舵机、IMU、传感器、LCD 屏、物理按键）。
- **软件核心：** Python 3 驱动的本地 UI 与机器人控制逻辑；Flask-SocketIO Web 控制台；多媒体与 AI Demo 集合。
- **核心流程：** `start1.sh` → `remix.py` → `main.py`，提供本地 UI 主菜单，三大入口分别为远程控制、热点/系统设置、Demo 体验。

---

## 2. 目录结构与职责

```text
RaspberryPi-CM4-main/
├── main.py                 # 本地主菜单，负责三大入口
├── demoen.py               # Demo 子菜单
├── hotspot.py              # 一键热点配置
├── flacksocket/            # Flask-SocketIO 远程控制台
│   ├── app.py              # Web 控制主程序
│   ├── camera_dog.py       # 摄像头采集与编码
│   ├── templates/          # Web 模板（demo.html 等）
│   └── static/             # 前端资源（CSS、Socket.IO、图标）
├── demos/                  # Demo 汇总（视觉、语音、系统工具）
│   ├── uiutils.py          # LCD 绘图、按键、语言、XGO 接口复用层
│   ├── robot.py            # 面向语音/视觉 Demo 的 UI 扩展
│   ├── speech/             # 语音唤醒、识别、LLM 互动
│   ├── xiaozhi_test/       # 实时语音对话模块
│   ├── expression/         # 面部表情帧动画
│   └── *.py                # 各类视觉/系统 Demo（color、hands 等）
├── language/               # 多语言配置（language.ini + *.la）
├── pics/                   # UI 素材与图标
└── volume/volume.ini       # 音量配置
```

---

## 3. 模块关系与交互

![模块关系示意](../RaspberryPi-CM4-main/pics/app.png)

| 模块 | 角色 | 与其他模块关系 |
| --- | --- | --- |
| `main.py` | 本地入口菜单 | 读取语言/电量/网络状态；按键控制跳转至远程控制 (`flacksocket`)、热点 (`hotspot.py`) 或 Demo (`demoen.py`) |
| `demos/uiutils.py` | 基础能力层 | 为 `main.py` 与各 Demo 初始化 LCD、按键、`xgolib.XGO` 实例，提供绘图、取电量等工具 |
| `demoen.py` | Demo 菜单 | 调用 `uiutils` 绘制网格菜单，`os.system` 触发表达式、视觉、语音等 Demo 脚本 |
| `flacksocket/app.py` | 远程控制台 | 启动 Flask-SocketIO 服务，结合 `camera_dog.py` 提供实时视频；通过 Socket 命令驱动 `xgolib.XGO` 动作 |
| `hotspot.py` | 网络配置 | 生成随机热点账号密码，调用 nmcli 设置热点，并在 LCD 呈现 |
| `demos/*` | Demo 体验 | 视觉类依托 OpenCV/Mediapipe；语音类依托 PyAudio、LLM API；系统类读写配置文件；统一借助 `uiutils`/`robot` 与 LCD、XGO、按键交互 |

---

## 4. 关键流程

### 4.1 主菜单循环
1. `main.py` 初始化 `Button`、语言包和 LCD。
2. 每隔 3 秒刷新电量与网络，渲染状态条与三大选项。
3. 按键 `C/D` 调整选项，`A` 确认执行：
   - 远程控制 → 启动 `flacksocket/app.py`。
   - 程序设置 → 启动 `hotspot.py` 创建热点。
   - Demo 体验 → 启动 `demoen.py` 进入 Demo 菜单。

### 4.2 Demo 菜单交互
1. `demoen.py` 调用 `uiutils` 构建背景与网格布局。
2. 通过 `MENU_ITEMS` 配置图标、脚本、文案映射。
3. 按键导航高亮选项，`A` 键加载对应脚本 (`os.system`)。
4. Demo 结束后返回菜单并刷新图标。

### 4.3 远程控制台
1. `flacksocket/app.py` 初始化 LCD 提示、读取本地 IP。
2. 启动 Flask-SocketIO 并开辟 `Process` 跑视频流 (`/camera` → `camera_dog.py`)。
3. Web 端通过 Socket 发送动作命令，后台调用 `xgolib.XGO` 的 `move_x/move_y/action/reset` 等接口。
4. LCD 根据访问状态切换在线/离线界面。

---

## 5. Demo 分类速览

### 视觉识别
- `face_mask.py` / `face_decetion.py`：面部检测与跟随。
- `hands.py`：Mediapipe 手势识别指令。
- `color.py`、`follow_line.py`、`ball.py`：颜色/轨迹识别与执行。

### 语音与智能体
- `speech/`：唤醒词（libnyumaya）、录音（PyAudio）、语音识别与豆包/Coze 等模型动作决策。
- `xiaozhi_test/`：实时语音对话方案（WebSocket 协议+UI）。

### 系统设置
- `language.py`：读写 `language.ini`，切换语言并重启主菜单。
- `volume.py`：调整 `volume.ini` + `pactl` 设置。
- `network.py` / `wifi_set.py`：二维码扫描与 wifi 配置。
- `device.py`：展示固件、库版本。

---

## 6. 运行要点与依赖

- **机器人控制：** 统一使用 `xgolib.XGO(port="/dev/ttyAMA0")`，需具备串口访问权限。
- **界面呈现：** `xgoscreen.LCD_2inch` + Pillow 绘制 UI 与动画。
- **硬件按键：** `RPi.GPIO` 定义 4 个物理键，广泛用于菜单与退出逻辑。
- **视觉处理：** OpenCV、Mediapipe、pyzbar（二维码）等。
- **语音处理：** PyAudio、libnyumaya、EdgeImpulse/豆包等 SDK。
- **网络操作：** `nmcli`、`wpa_cli`、`requests`（网络检测）。
- **前端控制：** Flask、Flask-SocketIO、Socket.IO.js、HTML/CSS。

---

## 7. 参考图像

![远程控制界面](../RaspberryPi-CM4-main/pics/app.png)

![语音界面示意](../RaspberryPi-CM4-main/pics/mic.png)

---

> 如需拓展 Demo，可在 `demos/` 中新增脚本并在 `demoen.py` 的 `MENU_ITEMS` 中注册，遵循 `uiutils` 提供的显示与按键接口，即可与主系统无缝对接。
