# 从 Bash 零基础到读懂 agent.sh

终点：[agent.sh](agent.sh)。学完后，你要能解释它的每个函数、追踪一次工具调用，并在练习目录运行它。

## 开始前

打开终端，建立一个专用练习目录：

```sh
mkdir -p ~/agent-craft-labs/bash
cd ~/agent-craft-labs/bash
```

每课的 Bash 代码都是完整脚本。把代码保存成 `lesson-01.sh`、`lesson-02.sh` 等，再运行 `bash lesson-01.sh`。不要用 `sh` 运行：后面会用 Bash 专有语法。可以先执行 `bash -n lesson-01.sh` 检查语法；没有输出表示语法检查通过，不代表运行逻辑正确。

第 10 课开始需要 `jq`。用 `jq --version` 检查是否安装；macOS 使用 Homebrew 时可执行 `brew install jq`，Ubuntu/Debian 可执行 `sudo apt-get install jq`。第 20 课还需要支持 `--fail-with-body` 的 `curl`。

## 第 01 课：命令与输出

**新概念：命令、参数、脚本入口。**

Bash 按顺序执行命令。空格把命令和参数分开；引号把含空格的文字保持为一个参数。第一行 shebang 表示直接执行脚本时使用哪个解释器；运行 `bash lesson-01.sh` 时，解释器已经由命令指定。

```bash
#!/usr/bin/env bash
pwd
printf 'Mini Coding Agent\n'
printf '下一步：%s\n' '接收用户任务'
```

`printf` 的第一个参数是格式，`%s` 放入后面的字符串，`\n` 表示换行。后面打印外部输入时统一用 `printf '%s\n' "$value"`，避免把输入中的 `%` 当格式指令。

**观察：** 先显示当前目录，再显示两行文字。

**练习：** 增加一行“工具：read_file”。验收：输出独占一行。

**回到终点：** 找到脚本末尾的启动提示，以及打印 `Agent：` 的位置。

## 第 02 课：变量与引号

**新概念：赋值、变量展开、单双引号。**

赋值时等号两侧不能有空格。单引号保留字面内容；双引号允许 `$变量` 展开，同时保留空格。把变量传给命令时，通常加双引号。

```bash
#!/usr/bin/env bash
MODEL='demo model'
TASK='读取 hello.txt'
printf '模型：%s\n' "$MODEL"
printf '任务：%s\n' "$TASK"
printf '%s\n' '$MODEL'
```

**观察：** 第一行包含完整的 `demo model`，最后一行是字面文字 `$MODEL`。

**练习：** 把任务改成 `写入 a b.txt`。验收：空格原样保留。这里仅练习字符串，最终文件工具不允许这种文件名。

**回到终点：** `API_URL`、`MODEL`、`TOOLS`、`MESSAGES` 都是变量；JSON 此时也只是字符串。

## 第 03 课：读取一行输入

**新概念：`read`、标准输入。**

`read` 从输入中读取一行，把结果写入变量。`-r` 表示保留反斜杠；`-p` 在交互输入时显示提示。

```bash
#!/usr/bin/env bash
USER_INPUT=''
read -r -p '> ' USER_INPUT
printf '收到：%s\n' "$USER_INPUT"
```

**观察：** 输入 `读取 hello.txt` 后按回车，脚本回显任务并结束。

**练习：** 输入 `a\b`。验收：回显仍包含反斜杠。

**回到终点：** `read_user_input` 包装的就是这条 `read` 命令。最终脚本没有设置 `IFS=`，所以输入首尾的默认分隔空白会被去掉；第 16 课再看保留整行的写法。

## 第 04 课：条件与退出状态

**新概念：退出状态、`if`、`[[ ... ]]`。**

命令除了输出文字，还会给出退出状态：`0` 表示成功，非零表示失败。`if` 判断的是命令的退出状态。`[[ ... ]]` 是 Bash 的条件命令，`-z` 检查字符串是否为空。

```bash
#!/usr/bin/env bash
USER_INPUT=''
if read -r -p '> ' USER_INPUT; then
  if [[ -z "$USER_INPUT" ]]; then
    printf '没有输入任务\n'
  elif [[ "$USER_INPUT" == exit ]]; then
    printf '准备退出\n'
  else
    printf '任务：%s\n' "$USER_INPUT"
  fi
else
  printf '输入已结束\n'
fi
```

**观察：** 分别输入空行、`exit`、普通任务，走三个分支。空行仍是读取成功；在空输入行按 Ctrl+D 才表示 EOF，让 `read` 返回失败。

**练习：** 增加 `help` 分支。验收：输入 `help` 时打印说明，普通任务仍会回显。

**回到终点：** `if has_tool_calls ...` 同样通过退出状态决定分支，并不比较输出文字。

## 第 05 课：持续接收任务

**新概念：`while`、`continue`、`break`。**

`while` 在条件命令成功时执行循环体。`continue` 跳过本轮剩余部分；`break` 退出当前循环。

```bash
#!/usr/bin/env bash
while read -r -p '> ' USER_INPUT; do
  if [[ -z "$USER_INPUT" ]]; then
    continue
  fi
  if [[ "$USER_INPUT" == exit ]]; then
    break
  fi
  printf '任务：%s\n' "$USER_INPUT"
done
printf '会话结束\n'
```

**观察：** 可以连续输入多条任务，空行不产生任务，`exit` 或 EOF 结束会话。

**练习：** 增加 `help` 分支并在打印说明后 `continue`。验收：`help` 不再作为任务打印。

**回到终点：** 这是文件最末尾的外层循环。它负责多个用户任务，与单个任务内部的模型循环不同。

## 第 06 课：函数、参数与局部变量

**新概念：函数、`$1`、`local`。**

函数把几条命令放在一个名字下。调用函数与调用命令一样；`$1` 是第一个参数。`local` 使变量属于当前函数调用，避免覆盖同名全局变量。

```bash
#!/usr/bin/env bash
USER_INPUT=''
read_user_input() {
  read -r -p '> ' USER_INPUT
}
show_task() {
  local task="$1"
  printf '任务：%s\n' "$task"
}
while read_user_input; do
  if [[ "$USER_INPUT" == exit ]]; then
    break
  fi
  show_task "$USER_INPUT"
done
```

**观察：** `read_user_input` 修改全局变量，`show_task` 只使用自己的局部变量。函数没有显式 `return` 时，状态就是最后一条命令的状态，所以 EOF 能结束循环。

**练习：** 给 `show_task` 增加第二个参数作为前缀。验收：调用 `show_task "$USER_INPUT" '用户'` 能显示“用户：任务内容”。

**回到终点：** `execute_tool` 的 `$1` 是工具名，`$2` 是参数 JSON。

## 第 07 课：接收函数输出

**新概念：`$(...)`、`return`、子 Shell。**

命令替换 `$(...)` 收集标准输出。函数用 `printf` 传回文本，用 `return` 传回退出状态，不能用 `return` 返回字符串。

```bash
#!/usr/bin/env bash
VALUE='外部'
make_answer() {
  VALUE='内部'
  printf '已读取文件\n\n'
  return 0
}
answer="$(make_answer)"
printf '答案：[%s]\n' "$answer"
printf 'VALUE：%s\n' "$VALUE"
```

**观察：** 答案末尾的换行被命令替换删除；`VALUE` 仍是“外部”，因为命令替换中的函数在子 Shell 环境中运行。

**练习：** 将最后一行改为直接调用 `make_answer`，然后打印 `VALUE`。验收：此时变为“内部”。

**回到终点：** `request="$(build_request)"` 收集输出；`append_user_message` 则必须直接调用，才能更新当前 Shell 中的 `MESSAGES`。最终脚本用命令替换读取文件内容字段，也会丢掉这些字段末尾的换行，这不是逐字节保真的存储方式。

## 第 08 课：文件与输出通道

**新概念：重定向、标准错误、管道。**

标准输出承载结果，标准错误承载诊断。`>` 写入并覆盖文件，`>>` 追加，`>&2` 写到标准错误，`|` 把前一条命令的标准输出送给后一条命令。

```bash
#!/usr/bin/env bash
printf 'hello\n' > note.txt
printf 'agent\n' >> note.txt
cat note.txt
printf '诊断：读取完成\n' >&2
cat note.txt | wc -l
```

**观察：** 文件包含两行，最后计数为 `2`。`cat note.txt | wc -l` 为了展示管道；单独计行可写 `wc -l < note.txt`。

`>/dev/null` 丢弃标准输出。`2>&1` 把标准错误接到标准输出当前去往的位置；`> log.txt 2>&1` 会把两种输出都放进文件，重定向顺序有意义。

**练习：** 执行 `bash lesson-08.sh > result.txt 2> error.txt`。验收：诊断只在 `error.txt`，文件内容和计数在 `result.txt`。

**回到终点：** `call_model` 的标准输出必须保持为响应正文；往这里打印日志会破坏后面的 JSON 解析。

## 第 09 课：把失败放进控制流程

**新概念：`&&` / `||`、`!`、`set -euo pipefail`。**

`A && B` 只在 A 成功时执行 B；`A || B` 只在 A 失败时执行 B。`!` 反转退出状态。花括号把多条命令组成一组。

```bash
#!/usr/bin/env bash
set -euo pipefail
command -v bash >/dev/null || { printf '缺少 bash\n' >&2; exit 1; }
status=0
bash -c 'printf "模拟失败\n" >&2; exit 7' || status=$?
printf '退出码：%s\n' "$status"
if ! [[ "$status" == 0 ]]; then
  printf '失败已经处理，脚本继续\n'
fi
```

`$?` 是刚刚结束的命令的状态；在其他命令覆盖它之前保存。`exit` 结束整个脚本，`return` 结束函数。这里的 `bash -c` 运行一段固定命令，后面会专门讨论它。

`-u` 对未定义变量报错；`pipefail` 使管道中任一命令失败时整个管道失败；`-e` 会在部分未处理的失败处退出。**不要把 `-e` 当异常处理系统。** `if` 条件、`!`、多数 `&&` / `||` 上下文有例外；函数作为这些条件执行时，函数体内的 `-e` 行为也会受影响。

**观察：** 退出码为 `7`，但脚本继续。不要在 `if ! command; then` 内用 `$?` 获取 command 的原始状态，它已经被 `!` 反转。

**练习：** 把子命令的 `exit 7` 改成 `exit 0`。验收：退出码为 `0`，不打印失败说明。

**回到终点：** `agent_loop || true` 保持交互会话继续运行；关键失败仍需显式判断，不能仅依赖文件开头的 `set -e`。

## 第 10 课：用 jq 读取 JSON

**新概念：JSON 字段、`jq -r`、here-string。**

模型响应是 JSON。对象用 `{}`，数组用 `[]`，字符串需要 JSON 转义。`jq` 解析这种结构；`<<<"$变量"` 将变量内容作为命令输入，并附加一个换行。

```bash
#!/usr/bin/env bash
response='{"choices":[{"message":{"role":"assistant","content":"你好"}}]}'
message="$(jq -c '.choices[0].message' <<<"$response")"
answer="$(jq -r '.content' <<<"$message")"
printf '消息：%s\n' "$message"
printf '答案：%s\n' "$answer"
jq -r '.missing // "没有这个字段"' <<<"$message"
```

`-c` 输出紧凑 JSON，适合继续放进变量；`-r` 将 JSON 字符串输出成普通文字。数组下标从 `0` 开始；`//` 在左边是 `null` 或 `false` 时使用右边的值。

**观察：** 消息仍是 JSON 对象，答案是没有外围双引号的“你好”。

**练习：** 将 `content` 改为 `null`，读取时改用 `.content // ""`。验收：答案为空字符串。

**回到终点：** `choices[0].message` 就是 `agent_loop` 从响应中选取的消息。

## 第 11 课：安全构造 JSON 与历史

**新概念：`--arg`、`--argjson`、数组追加。**

不要用字符串拼接构造 JSON。`--arg` 传入普通字符串，由 jq 转义；`--argjson` 传入已经合法的 JSON 值。`-n` 表示不从标准输入读取 JSON。

```bash
#!/usr/bin/env bash
MESSAGES="$(jq -nc '[{role:"system",content:"你是简洁的助手"}]')"
append_user_message() {
  MESSAGES="$(jq -c --arg content "$1" \
    '. + [{role:"user",content:$content}]' <<<"$MESSAGES")"
}
append_user_message '读取 "hello.txt"，保留 a\b'
message='{"role":"assistant","content":"好的"}'
MESSAGES="$(jq -c --argjson message "$message" '. + [$message]' <<<"$MESSAGES")"
jq . <<<"$MESSAGES"
```

Bash 单引号里的 `$content` 是 jq 变量，不是 Shell 变量。行末 `\` 让命令延续到下一行；它后面不能再跟空格。

**观察：** 历史有 system、user、assistant 三项，用户文字中的双引号和反斜杠得到正确转义。

**练习：** 再调用一次 `append_user_message`。验收：`jq 'length'` 得到 `4`，前面的消息没有丢失。

**回到终点：** assistant 消息整体追加，才能保留其中的 `tool_calls`。

## 第 12 课：让 JSON 决定分支

**新概念：`jq -e`、`select`。**

`jq -e` 将结果与退出状态连接：最后结果为 `false` 或 `null` 时失败，其他正常结果成功；无结果或解析错误也会失败。这样可以直接放进 `if`。

```bash
#!/usr/bin/env bash
has_tool_calls() {
  jq -e '(.tool_calls // []) | length > 0' >/dev/null <<<"$1"
}
message='{"role":"assistant","content":"完成"}'
if has_tool_calls "$message"; then
  printf '执行工具\n'
else
  printf '显示最终答案\n'
fi
response='{"choices":[{"message":{"role":"assistant","content":"完成"}}]}'
if parsed="$(jq -ce '.choices[0].message | select(.role == "assistant")' <<<"$response")"; then
  printf '%s\n' "$parsed"
else
  printf '响应不含有效 assistant 消息\n' >&2
fi
```

`select(条件)` 只让符合条件的值通过；`-ce` 等于同时使用 `-c` 和 `-e`。

**观察：** 没有 `tool_calls` 时显示最终答案，合法响应被保留下来。

**练习：** 把响应中的角色改为 `user`。验收：进入错误分支。再把第一条消息加上非空 `tool_calls` 数组，确认进入工具分支。

**回到终点：** 这些判断只覆盖脚本关心的结构，并不是完整的响应 schema 校验。

## 第 13 课：分派文件工具

**新概念：`case`、文件名校验、文件测试。**

`case` 根据工具名选择分支，`;;` 结束一个分支，`*` 匹配其他名称。`[[ -f ... ]]` 检查路径是否为普通文件。`=~` 使用正则表达式，右边的正则不加引号；`==` / `!=` 右边未引用的 `*` 是通配符。

```bash
#!/usr/bin/env bash
valid_filename() {
  [[ "$1" =~ ^[A-Za-z0-9][A-Za-z0-9._-]*$ && "$1" != *..* ]]
}
execute_tool() {
  local name="$1" args="$2" filename content
  if ! jq -e 'type == "object"' >/dev/null 2>&1 <<<"$args"; then
    printf '错误：参数必须是 JSON 对象\n'
    return
  fi
  filename="$(jq -r '.filename // empty' <<<"$args")"
  if ! valid_filename "$filename"; then
    printf '错误：只接受简单文件名\n'
    return
  fi
  case "$name" in
    write_file)
      content="$(jq -r '.content // empty' <<<"$args")"
      printf '%s' "$content" > "$filename"
      printf '已写入 %s\n' "$filename"
      ;;
    read_file)
      if [[ -f "$filename" ]]; then
        head -c 12000 -- "$filename"
      else
        printf '错误：文件不存在\n'
      fi
      ;;
    *) printf '错误：未知工具\n' ;;
  esac
}
execute_tool write_file '{"filename":"hello.txt","content":"hello agent"}'
execute_tool read_file '{"filename":"hello.txt"}'
printf '\n'
execute_tool read_file '{"filename":"../secret.txt"}'
```

`empty` 是 jq 的“不输出值”，不是字符串。`head -c 12000` 最多输出 12000 字节；`--` 表示后面的参数不再按选项解析。错误文字在这里作为工具结果，函数不一定以非零状态退出。

**观察：** 先写入再读取 `hello agent`，带路径的名称被拒绝。

**练习：** 在写入前增加 `if (( ${#content} > 12000 )); then ...` 分支，超限就返回错误。`${#content}` 是字符串长度，`(( ... ))` 计算整数条件。验收：超长内容不会覆盖旧文件。这正是最终脚本的写入限制。

**回到终点：** 文件名规则也拒绝 `.hidden`、中文名和 `a..b`。它不是沙箱：符号链接仍可能指向目录外，`bash` 工具也不受此规则限制。只在自己控制的练习目录运行。

## 第 14 课：只替换唯一的一处文本

**新概念：临时文件、`--rawfile`、jq 的拆分与连接。**

直接把转换结果重定向到原文件，可能在读取前就清空原文件。先把完整结果写入临时文件，确认转换成功后再写回。

```bash
#!/usr/bin/env bash
printf 'hello agent\n' > edit-demo.txt
old_text='hello'
new_text='你好'
temp="$(mktemp)"
if jq -n -j --rawfile original edit-demo.txt \
  --arg old "$old_text" --arg new "$new_text" \
  '($original | split($old)) as $parts |
   if ($parts | length) == 2 then $parts | join($new)
   else error("旧文本不存在或出现多次") end' > "$temp"; then
  cat "$temp" > edit-demo.txt
  printf '已修改\n'
else
  printf '匹配失败，原文件未修改\n'
fi
unlink "$temp"
cat edit-demo.txt
```

`mktemp` 创建临时文件并输出路径，`unlink` 删除该临时文件。`--rawfile` 把整个文件作为字符串交给 jq，`-j` 输出原始字符串且不额外追加换行。`split` 按字面字符串拆分：恰好匹配一次会得到两段；`join` 用新文本连接。`as $parts` 为中间结果命名。

**观察：** 输出“你好 agent”，保留文件末尾原有的换行。

**练习：** 将初始文件分别改为 `hello hello` 和 `goodbye`。验收：两次都拒绝修改，保留原内容。

**回到终点：** `edit_file` 在此基础上先验证文件名、文件存在和旧文本非空。这里与原脚本一样按不重叠匹配计数；临时文件保护转换失败，但 `cat > 原文件` 不是原子替换，写入中断仍可能损坏文件。

## 第 15 课：运行命令并保留失败信息

**新概念：`bash -c`、单次环境变量、字符串截取。**

文件工具处理数据；`bash -c` 会把字符串当成完整程序执行。下面只运行一条我们自己写的固定命令。

```bash
#!/usr/bin/env bash
run_command() {
  local command="$1" output status
  status=0
  output="$(DEEPSEEK_API_KEY= bash -c "$command" 2>&1)" || status=$?
  printf '退出码：%s\n%s\n' "$status" "${output:0:12000}"
}
run_command 'printf "测试输出\n"; printf "测试错误\n" >&2; exit 3'
```

`DEEPSEEK_API_KEY=` 只为这次命令及其后代设置空密钥，不改变父 Shell 的变量。`${output:0:12000}` 从位置 0 截取最多 12000 个字符；完整输出已经先被收集进内存，这不是内存上限，也不是超时限制。

**观察：** 状态为 `3`，普通输出和错误输出都出现在结果中。

**练习：** 换成固定命令 `pwd`，再换成 `exit 5`。验收：分别报告 `0` 和 `5`，脚本能正常打印结果。

**回到终点：** 最终 `bash` 工具执行模型给出的命令。清空一个密钥变量不等于隔离文件系统、网络或其他凭据；接入真实模型后仅在无敏感资料的受控环境练习。

## 第 16 课：逐个读取工具调用

**新概念：`IFS=`、进程替换 `< <(...)`。**

模型一次可能请求多个工具。`jq -c '.tool_calls[]'` 每行输出一个调用对象，循环逐行处理。`IFS=` 防止 `read` 去掉行首尾分隔空白；`-r` 保留反斜杠。

```bash
#!/usr/bin/env bash
MESSAGES='[]'
message='{"tool_calls":[{"id":"call_1"},{"id":"call_2"}]}'
while IFS= read -r call; do
  id="$(jq -r '.id' <<<"$call")"
  MESSAGES="$(jq -c --arg id "$id" \
    '. + [{role:"tool",tool_call_id:$id,content:"完成"}]' <<<"$MESSAGES")"
done < <(jq -c '.tool_calls[]' <<<"$message")
jq . <<<"$MESSAGES"
```

两个 `<` 职责不同：第一个把输入重定向给循环，`<(...)` 将命令输出提供为可读取的来源。循环留在当前 Shell，因此 `MESSAGES` 的修改可以保留。常见的 `producer | while ...` 在 Bash 默认配置下会让循环运行在子 Shell 中，变量修改无法带回。

**观察：** 循环结束后历史中有两条工具消息。

**练习：** 增加 `call_3`。验收：最终数组长度为 `3`，三个 ID 都保留。

**回到终点：** `execute_tool_calls` 还从每个对象读取 `.function.name` 和 `.function.arguments`，执行后追加结果。arguments 是“包含 JSON 文本的字符串”，所以先用 `jq -r` 取出，再当 JSON 解析。

## 第 17 课：给任务设置轮数上限

**新概念：算术 `for`、有界内层循环。**

外层循环接收用户任务；内层循环推进一个任务。单轮可以执行多个工具，因此模型轮数不等于工具调用次数。

```bash
#!/usr/bin/env bash
MAX_ROUNDS=3
agent_loop() {
  local round
  for ((round = 1; round <= MAX_ROUNDS; round++)); do
    printf '模型第 %s 轮\n' "$round"
    if [[ "$round" == 2 ]]; then
      printf '得到最终答案\n'
      return 0
    fi
    printf '执行工具，准备下一轮\n'
  done
  printf '达到最大轮数\n' >&2
  return 1
}
agent_loop || printf '当前任务没有完成\n'
```

**观察：** 第二轮返回成功，没有第三轮。`return` 退出整个函数，不只是循环。

**练习：** 把结束条件从 `2` 改为 `99`。验收：只执行三轮，报告上限并返回失败。

**回到终点：** 原脚本上限是 12 次模型请求；最后一轮如果仍然请求工具，脚本会执行工具，然后报告达到上限，不再请求模型总结。

## 第 18 课：离线拼出一个完整 Agent Loop

**新概念：工具调用协议。** 本课只组合前面学过的 Bash 语法。

模型返回 `tool_calls` 是提出调用；本地脚本执行后以 `role: "tool"` 回传结果。`tool_call_id` 必须与调用的 `id` 对应。历史顺序是：system → user → assistant（调用）→ tool（结果）→ assistant（答案）。

下面的 `call_model` 用固定 JSON 模拟模型：先请求读取文件，看到工具结果后才回答。没有网络请求，也不会执行任意命令。

```bash
#!/usr/bin/env bash
set -euo pipefail
MAX_ROUNDS=3
MESSAGES='[{"role":"system","content":"读取文件后回答"}]'
printf 'hello agent\n' > mock-note.txt
append_message() {
  MESSAGES="$(jq -c --argjson message "$1" '. + [$message]' <<<"$MESSAGES")"
}
call_model() {
  if jq -e '.[-1].role == "tool"' >/dev/null <<<"$MESSAGES"; then
    jq -nc --arg content "$(jq -r '.[-1].content' <<<"$MESSAGES")" \
      '{role:"assistant",content:("文件内容：" + $content)}'
  else
    jq -nc --arg args '{"filename":"mock-note.txt"}' \
      '{role:"assistant",content:null,tool_calls:[{id:"call_1",type:"function",function:{name:"read_file",arguments:$args}}]}'
  fi
}
execute_tool() {
  local name="$1" args="$2" filename
  filename="$(jq -r '.filename' <<<"$args")"
  if [[ "$name" == read_file && "$filename" == mock-note.txt ]]; then
    cat mock-note.txt
  else
    printf '错误：此演示只允许读取 mock-note.txt'
  fi
}
agent_loop() {
  local round message call id name args result
  for ((round = 1; round <= MAX_ROUNDS; round++)); do
    message="$(call_model)"
    append_message "$message"
    if jq -e '(.tool_calls // []) | length > 0' >/dev/null <<<"$message"; then
      while IFS= read -r call; do
        id="$(jq -r '.id' <<<"$call")"
        name="$(jq -r '.function.name' <<<"$call")"
        args="$(jq -r '.function.arguments' <<<"$call")"
        result="$(execute_tool "$name" "$args")"
        append_message "$(jq -nc --arg id "$id" --arg content "$result" \
          '{role:"tool",tool_call_id:$id,content:$content}')"
      done < <(jq -c '.tool_calls[]' <<<"$message")
    else
      jq -r '.content // ""' <<<"$message"
      return 0
    fi
  done
  printf '达到最大轮数\n' >&2
  return 1
}
while read -r -p '> ' USER_INPUT; do
  [[ -z "$USER_INPUT" ]] && continue
  [[ "$USER_INPUT" == exit ]] && break
  append_message "$(jq -nc --arg content "$USER_INPUT" '{role:"user",content:$content}')"
  agent_loop || true
  jq -e '.[-3].tool_calls[0].id == .[-2].tool_call_id and .[-1].role == "assistant"' \
    >/dev/null <<<"$MESSAGES" || { printf '历史顺序检查失败\n' >&2; exit 1; }
done
```

**观察：** 输入任意非空任务后，得到“文件内容：hello agent”。离线模型不理解任务文字，每次都请求同一个工具。末尾包含一条可运行的协议检查，检查调用与结果是否配对。

**练习：** 在任务完成后加 `jq . <<<"$MESSAGES"`。连续输入两条任务，验收：历史长度依次为 `5`、`9`，第二个任务没有清空第一段历史。

**回到终点：** 对照 `append_assistant_message`、`append_tool_result`、`execute_tool_calls` 和 `agent_loop`。原版将这里通用的追加函数拆成按角色命名的函数，并添加真实响应解析与错误处理。

## 第 19 课：构造真实请求，但暂不发送

**新概念：工具描述、请求体。**

工具描述说明工具名、用途和参数结构；它不会执行代码。这里的 `TOOLS` 是 JSON 数组字符串，不能当作 Bash 数组使用。

```bash
#!/usr/bin/env bash
MODEL='demo-model'
MESSAGES='[{"role":"user","content":"读取 hello.txt"}]'
TOOLS='[{"type":"function","function":{"name":"read_file","description":"读取文件","parameters":{"type":"object","properties":{"filename":{"type":"string"}},"required":["filename"]}}}]'
build_request() {
  jq -nc --arg model "$MODEL" --argjson messages "$MESSAGES" --argjson tools "$TOOLS" \
    '{model:$model,messages:$messages,tools:$tools,tool_choice:"auto",thinking:{type:"disabled"}}'
}
request="$(build_request)"
printf '%s\n' "$request" | jq .
```

**观察：** `messages` 和 `tools` 都是数组，`model` 是字符串。`tool_choice: "auto"` 让模型选择回答或请求工具。`thinking` 是原脚本使用的服务参数，不是 Bash 语法，也不是所有服务通用的字段。

**练习：** 在 `TOOLS` 中添加 `write_file` 描述，参数含 `filename` 和 `content`。验收：请求中的工具数量为 `2`，且能由 `jq` 正常解析。描述与本地实现必须配套，添加描述本身不会增加执行能力。

**回到终点：** 原版有四个描述，与 `execute_tool` 的四个分支一一对应。

## 第 20 课：环境变量、HTTP 与终点脚本

**新概念：环境变量、参数默认值与必填检查、`curl`。**

`export` 让子进程继承变量。`${变量:-默认值}` 在变量未设置或为空时使用默认值；`${变量:?提示}` 在同样情况下报错并终止非交互 Shell。`:` 是不做事但会展开参数的命令，所以常用来触发必填检查。

先阅读下面的联网脚本，再配置自己的密钥。它只请求一次普通回答，不执行模型生成的命令。示例沿用当前仓库 `agent.sh` 的服务地址、默认模型名和参数；是否可用取决于服务及账户，必要时用账户支持的模型覆盖 `DEEPSEEK_MODEL`。

```bash
#!/usr/bin/env bash
set -euo pipefail
command -v curl >/dev/null || { printf '缺少 curl\n' >&2; exit 1; }
command -v jq >/dev/null || { printf '缺少 jq\n' >&2; exit 1; }
: "${DEEPSEEK_API_KEY:?请先设置 DEEPSEEK_API_KEY}"
MODEL="${DEEPSEEK_MODEL:-deepseek-flash}"
request="$(jq -nc --arg model "$MODEL" \
  '{model:$model,messages:[{role:"user",content:"用一句话解释 Bash"}],thinking:{type:"disabled"}}')"
if response="$(curl --silent --show-error --fail-with-body \
  --connect-timeout 10 --max-time 120 \
  'https://api.deepseek.com/chat/completions' \
  -H "Authorization: Bearer $DEEPSEEK_API_KEY" \
  -H 'Content-Type: application/json' \
  --data-binary "$request")"; then
  jq -er '.choices[0].message.content' <<<"$response"
else
  printf '请求失败，请检查网络、账户权限与模型配置\n' >&2
  exit 1
fi
```

`-H` 添加请求头，`--data-binary` 发送请求正文，并让这里的请求使用 POST。`--silent --show-error` 隐藏进度条但保留错误；`--fail-with-body` 使 HTTP 错误产生非零状态；两个 timeout 分别限制连接阶段和整个请求耗时。

在 **Bash 终端**中输入下面几行。`-s` 让密钥输入不回显，密钥也不会作为明文命令进入 Shell 历史：

```sh
read -r -s -p 'DeepSeek API Key: ' DEEPSEEK_API_KEY
printf '\n'
export DEEPSEEK_API_KEY
bash lesson-20.sh
```

**观察：** 正常情况输出一句解释；没有密钥时，必填检查在发送请求前失败。不要用 `bash -x` 调试携带真实密钥的请求，否则展开的请求头可能被打印。

**练习：** 先用 `(unset DEEPSEEK_API_KEY; bash lesson-20.sh)` 验证缺少密钥时退出，再用真实配置请求一次。圆括号运行在子 Shell 中，不会清除当前终端的密钥。验收：两个分支都符合预期，不要求模型逐字返回某个固定答案。

### 运行原版 agent.sh

把本仓库的 `agent.sh` 复制到刚才的专用练习目录。在该目录中，复用已导出的密钥，运行：

```sh
printf 'hello agent\n' > hello.txt
bash agent.sh
```

依次尝试以下任务，每次等待回复后再输入下一条：

1. `读取 hello.txt，告诉我内容。`
2. `把 hello.txt 中的 hello 改成 hi，其他内容保持不变。`
3. `运行 cat hello.txt，检查修改结果。`
4. `exit`

验收：文件变为 `hi agent`；终端能看到工具调用及结果；`exit` 结束会话。模型可能一次请求多个工具，路径不必与示例逐轮一致。原脚本能覆盖文件和运行任意 Bash 命令，练习目录中的文件应当都是可丢弃的。

### 按数据流读完终点

| 顺序 | 原脚本位置 | 用前面哪几课解释 |
| --- | --- | --- |
| 1 | shebang、严格选项、依赖与密钥检查 | 01、09、20 |
| 2 | API_URL、MODEL、MAX_ROUNDS、TOOLS、MESSAGES | 02、11、17、19 |
| 3 | read_user_input、最末尾 while | 03～06 |
| 4 | append_user_message、append_assistant_message | 07、11 |
| 5 | build_request、call_model | 08、19、20 |
| 6 | 响应解析、has_tool_calls | 10、12 |
| 7 | valid_filename、execute_tool 四个分支 | 13～15 |
| 8 | execute_tool_calls、append_tool_result | 11、16、18 |
| 9 | agent_loop 的返回与轮数耗尽 | 09、17、18 |

**毕业练习：** 在纸上追踪“读取 hello.txt”这个任务，为每一步写出当前消息的 role，圈出真正发生文件读取的函数，再指出两个循环各自在什么条件下结束。

参考验收：外层循环在 `exit` 或 EOF 时结束；内层循环在最终回答、请求失败、响应解析失败或达到轮数上限时结束。模型先提出调用，本地 `execute_tool` 真正读文件；工具结果与调用 ID 配对后进入下一次请求。能够解释这条链路，就达到了本教程的终点。
