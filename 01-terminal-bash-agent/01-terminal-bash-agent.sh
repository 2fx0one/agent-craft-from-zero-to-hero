#!/usr/bin/env bash
# Mini Coding Agent：外层循环接收用户任务，内层循环让模型反复决定下一步。
# 依赖 curl、jq；运行前设置 DEEPSEEK_API_KEY。
set -euo pipefail
# -e：未处理的命令失败时退出；-u：使用未定义变量时报错；
# pipefail：管道中任一命令失败时，整条管道视为失败。

command -v curl >/dev/null || { echo '缺少 curl' >&2; exit 1; }
command -v jq >/dev/null || { echo '缺少 jq' >&2; exit 1; }
: "${DEEPSEEK_API_KEY:?请先设置 DEEPSEEK_API_KEY}"

API_URL='https://api.deepseek.com/chat/completions'
MODEL="${DEEPSEEK_MODEL:-deepseek-flash}"
MAX_ROUNDS=12
# 给单个任务设上限，避免模型一直请求工具而无法结束。

# 工具描述会发给模型；实际操作由 execute_tool 执行。
# 这里是 JSON 数组：每项定义工具名、用途和参数结构。
# 模型只能“提出调用”；脚本收到 tool_calls 后才执行本地操作。
TOOLS='[
  {"type":"function","function":{"name":"read_file","description":"读取当前目录中的文件","parameters":{"type":"object","properties":{"filename":{"type":"string","description":"不含路径的文件名"}},"required":["filename"]}}},
  {"type":"function","function":{"name":"write_file","description":"创建或覆盖当前目录中的文件","parameters":{"type":"object","properties":{"filename":{"type":"string","description":"不含路径的文件名"},"content":{"type":"string","description":"完整文件内容"}},"required":["filename","content"]}}},
  {"type":"function","function":{"name":"edit_file","description":"把文件中唯一一处旧文本替换为新文本；先 read_file 获取精确内容","parameters":{"type":"object","properties":{"filename":{"type":"string","description":"不含路径的文件名"},"old_text":{"type":"string","description":"文件中原有的完整片段，必须只出现一次"},"new_text":{"type":"string","description":"替换后的文本"}},"required":["filename","old_text","new_text"]}}},
  {"type":"function","function":{"name":"bash","description":"在当前工作目录执行 Bash 命令，返回输出和退出码；可用于 pwd、ls、测试等","parameters":{"type":"object","properties":{"command":{"type":"string","description":"要执行的 Bash 命令"}},"required":["command"]}}}
]'

MESSAGES="$(jq -nc '[{"role":"system","content":"你是简洁的编码助手。可用 read_file、write_file、edit_file、bash 四个工具。先查看必要的文件再修改。文件工具只接受当前目录的简单文件名；bash 可执行命令。完成后简要报告。"}]')"
# MESSAGES 是 JSON 数组，保留 system、user、assistant 和 tool 的完整历史。
# 下一次请求会发送整段历史，模型才能根据上次工具结果继续决策。
USER_INPUT=''

# 1. 接收用户输入。EOF（Ctrl-D）时返回失败，主循环退出。
read_user_input() {
  # -r 保留输入中的反斜杠；-p 显示提示语。
  # read 把内容赋给全局 USER_INPUT，函数的退出状态用于识别 EOF。
  read -r -p '> ' USER_INPUT
}

# --arg 安全地把普通字符串传给 jq；jq 负责 JSON 转义。
append_user_message() {
  MESSAGES="$(jq -c --arg content "$1" '. + [{role:"user",content:$content}]' <<<"$MESSAGES")"
}

append_assistant_message() {
  # assistant 消息可能包含 tool_calls，必须原样存入历史。
  # --argjson 把参数当 JSON 值，而不是带引号的普通字符串。
  MESSAGES="$(jq -c --argjson message "$1" '. + [$message]' <<<"$MESSAGES")"
}

# 2. 构造请求。关闭思考模式，入门课暂不处理 reasoning_content。
build_request() {
  # -n 不读输入，-c 输出紧凑 JSON；jq 把三个变量组装为请求体。
  # 函数无需显式 return JSON：命令打印到 stdout，调用者用 $(...) 接收。
  # Bash 的 return 只返回 0～255 的退出状态。
  jq -nc --arg model "$MODEL" --argjson messages "$MESSAGES" --argjson tools "$TOOLS" \
    '{model:$model,messages:$messages,tools:$tools,tool_choice:"auto",thinking:{type:"disabled"}}'
}

# 3. 请求 DeepSeek。API Key 只放在请求头，不打印。
call_model() {
  # $1 是 build_request 产出的 JSON；响应正文打印到 stdout。
  # --fail-with-body 使 HTTP 错误产生非零退出状态，供调用者判断。
  curl --silent --show-error --fail-with-body \
    --connect-timeout 10 --max-time 120 \
    "$API_URL" \
    -H "Authorization: Bearer $DEEPSEEK_API_KEY" \
    -H 'Content-Type: application/json' \
    --data-binary "$1"
}

# 4. 判断模型是否请求了工具。
has_tool_calls() {
  # // [] 表示字段缺失或为 null 时用空数组；length > 0 得到布尔值。
  # jq -e 把 true/false 转为成功/失败的退出状态，输出丢弃到 /dev/null。
  # 所以可直接写 if has_tool_calls "$message"; then ...
  jq -e '(.tool_calls // []) | length > 0' >/dev/null <<<"$1"
}

valid_filename() {
  # 文件工具只接收当前目录中的简单名称，禁止路径分隔符和 ..。
  # 这条限制不适用于 bash 工具；bash 会执行模型提供的完整命令。
  [[ "$1" =~ ^[A-Za-z0-9][A-Za-z0-9._-]*$ && "$1" != *..* ]]
}

# 5. 执行一个工具。将操作结果输出到 stdout。
execute_tool() {
  local name="$1" args="$2" filename content old_text new_text command output status temp

  if ! jq -e 'type == "object"' >/dev/null 2>&1 <<<"$args"; then
    # 参数必须是可解析的 JSON 对象；错误文本也作为工具结果返回模型。
    printf '错误：工具参数不是 JSON 对象'
    return
  fi

  case "$name" in
    read_file)
      # 从 arguments JSON 中取出 filename，再验证和读取。
      filename="$(jq -r '.filename // empty' <<<"$args")"
      if ! valid_filename "$filename"; then
        printf '错误：只接受当前目录中的简单文件名'
      elif [[ ! -f "$filename" ]]; then
        printf '错误：文件不存在：%s' "$filename"
      else
        head -c 12000 -- "$filename"
      fi
      ;;
    edit_file)
      # old_text 必须恰好出现一次，否则不写回文件。
      # 临时文件先生成完整的新内容，再复制回原文件。
      filename="$(jq -r '.filename // empty' <<<"$args")"
      old_text="$(jq -r '.old_text // empty' <<<"$args")"
      new_text="$(jq -r '.new_text // empty' <<<"$args")"
      if ! valid_filename "$filename"; then
        printf '错误：只接受当前目录中的简单文件名'
      elif [[ ! -f "$filename" ]]; then
        printf '错误：文件不存在：%s' "$filename"
      elif [[ -z "$old_text" ]]; then
        printf '错误：old_text 不能为空'
      else
        temp="$(mktemp)"
        if jq -n -j --rawfile original "$filename" \
          --arg old "$old_text" --arg new "$new_text" \
          '($original | split($old)) as $parts |
           if ($parts | length) == 2 then $parts | join($new)
           else error("old_text 不存在或出现多次") end' > "$temp" 2>/dev/null; then
          cat "$temp" > "$filename"
          printf '已修改 %s' "$filename"
        else
          printf '错误：old_text 不存在或出现多次，文件未修改'
        fi
        unlink "$temp"
      fi
      ;;
    bash)
      # bash -c 执行给定命令。命令输出和退出码都会作为观察结果。
      # 清空子进程中的 API Key；这里没有命令白名单，请仅在可信目录运行。
      command="$(jq -r '.command // empty' <<<"$args")"
      if [[ -z "$command" ]]; then
        printf '错误：command 不能为空'
      else
        status=0
        output="$(DEEPSEEK_API_KEY= bash -c "$command" 2>&1)" || status=$?
        printf '退出码：%s\n%s' "$status" "${output:0:12000}"
      fi
      ;;
    write_file)
      # 覆盖整个文件；content 来自 JSON 参数，printf 避免解释反斜杠。
      filename="$(jq -r '.filename // empty' <<<"$args")"
      content="$(jq -r '.content // empty' <<<"$args")"
      if ! valid_filename "$filename"; then
        printf '错误：只接受当前目录中的简单文件名'
      elif (( ${#content} > 12000 )); then
        printf '错误：内容超过 12000 字符'
      else
        printf '%s' "$content" > "$filename"
        printf '已写入 %s' "$filename"
      fi
      ;;
    *)
      printf '错误：未知工具：%s' "$name"
      ;;
  esac
}

# 6. 把工具结果送回消息历史。id 必须对应模型发出的 tool_call id。
append_tool_result() {
  # role=tool 的消息让模型“看到”执行结果，并与对应的调用配对。
  MESSAGES="$(jq -c --arg id "$1" --arg content "$2" \
    '. + [{role:"tool",tool_call_id:$id,content:$content}]' <<<"$MESSAGES")"
}

execute_tool_calls() {
  local message="$1" call id name args result
  # 模型一次可以请求多个工具。逐个执行、逐个追加 tool 消息。
  # 这里用进程替换而非管道，避免 while 在子 Shell 中修改 MESSAGES。
  while IFS= read -r call; do
    id="$(jq -r '.id' <<<"$call")"
    name="$(jq -r '.function.name' <<<"$call")"
    args="$(jq -r '.function.arguments' <<<"$call")"
    printf '  → %s %s\n' "$name" "$args"
    result="$(execute_tool "$name" "$args")"
    printf '  ← %s\n' "$result"
    append_tool_result "$id" "$result"
  done < <(jq -c '.tool_calls[]' <<<"$message")
}

agent_loop() {
  local round request response message answer
  # 每轮：组装历史 → 调用模型 → 保存 assistant 消息 →
  # 若有 tool_calls，则执行并保存结果，再重新调用模型。
  # 若没有 tool_calls，当前回复就是最终答案，结束当前任务。
  for ((round = 1; round <= MAX_ROUNDS; round++)); do
    request="$(build_request)"
    if ! response="$(call_model "$request")"; then
      echo 'DeepSeek 请求失败' >&2
      return 1
    fi
    if ! message="$(jq -ce '.choices[0].message | select(.role == "assistant")' <<<"$response")"; then
      printf '无法解析模型回复：%s\n' "$response" >&2
      return 1
    fi

    append_assistant_message "$message"
    if has_tool_calls "$message"; then
      execute_tool_calls "$message"
    else
      # 没有工具调用时，把普通文本作为本轮最终回复。
      answer="$(jq -r '.content // ""' <<<"$message")"
      printf 'Agent：%s\n' "$answer"
      return 0
    fi
  done
  echo '达到最大轮数，停止当前任务' >&2
  return 1
}

echo 'Mini Coding Agent 已启动。输入 exit 退出。'
# 外层循环负责持续接收新任务；MESSAGES 不重置，因此保留会话上下文。
while read_user_input; do
  [[ -z "$USER_INPUT" ]] && continue
  [[ "$USER_INPUT" == exit ]] && break
  append_user_message "$USER_INPUT"
  agent_loop || true
done
