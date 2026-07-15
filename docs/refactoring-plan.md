# ethereum-lisp 源码布局重构方案

## 文档定位

本文档描述源码物理布局重构的执行边界、依赖模型和验证方式。重构只改变文件路径与
ASDF 装配方式，不改变协议行为、公开 API、package 名、符号所有权、数据库键或
序列化格式。

逐文件迁移以 [`refactoring-source-map.tsv`](refactoring-source-map.tsv) 为唯一清单。
清单覆盖当前 304 个 production Lisp 文件，并记录旧路径、新路径、package owner 和
逻辑模块。

## 现状与目标

原有 `src/` 把绝大多数实现文件放在根目录，文件名前缀同时承担了目录、领域和职责
说明。现有 package 边界和架构测试是可靠基础，应完整保留；需要改善的是物理布局和
ASDF 对依赖关系的表达。

目标如下：

1. 目录直接反映 foundation、protocol、runtime、storage、application、API、
   transport 和 app 的所有权层次；
2. owner 已由目录表达时，去掉重复文件名前缀；
3. 保持所有源码内容、package 声明、导出符号和加载语义不变；
4. 先完成可验证的纯移动，再单独收紧 ASDF 模块依赖；
5. 小文件合并作为后续独立审核，不与路径迁移混合。

## 非目标

- 不修改 EVM、共识、Engine API、RPC、持久化或 CLI 行为；
- 不重命名 package，也不删除 `ethereum-lisp` / `ethereum-lisp.core` 兼容层；
- 不借目录调整重写实现、测试或 fixture；
- 不把小文件合并、抽象提取和功能修复混入纯移动变更；
- 不把物理目录直接等同于新的 package 边界。

## 经核对的逻辑依赖

目录归属与 ASDF 逻辑模块不能简单一一对应。正确的实现层依赖是：

```text
packages (declarations only)
foundation
  -> protocol
       -> runtime-core -----------+
       -> storage-core -----------+-> application-services
                                          |-> persistence-adapters
                                          +-> API -> transport
persistence-adapters + transport ------------> app
```

其中有几个容易误分层的桥接点：

- `execution-service` 同时使用纯 execution、state、chain-store 和 node-store，属于
  `application-services`；
- `canonical-chain` 协调 chain-store、txpool、reorg 和 filter 通知，属于
  `application-services`；
- `txpool.application` 是交易预检与准入服务，不是 txpool 存储实现；
- `engine` 的 payload status 决策使用 store，属于应用服务，不是 protocol model；
- `genesis-state` 连接 genesis 输入与 mutable state，属于应用服务；
- persistence 文件物理上位于 `storage/node-store/persistence/`，但逻辑上必须是独立的
  `persistence-adapters` 模块。`staged-import.lisp` 调用 `execution-service`，因此它依赖
  application services，不能作为 `storage-core` 的子模块提前加载。

这修正了按 `runtime -> storage -> service` 粗粒度分层会形成循环依赖的问题。

## 目标目录

```text
src/
  packages/
  foundation/
    database/
    crypto/
    trie/
    json/
  protocol/
    chain-config/
    accounts/
    transactions/
    receipts/
    execution-requests/
    block-access-lists/
    blocks/
    consensus/
    genesis/
    kzg/
    engine-payloads/
  runtime/
    state/
    evm/
      opcodes/
      precompiles/
      interpreter/
    execution/
  storage/
    chain-store/
      model/
      state/
      service/
    txpool/
      index/
      service/
    node-store/
      persistence/
        export/
        import/
  application/
    services/
  api/
    json-rpc/
    engine/
    public/
    rpc/
  transport/
    http/
  app/
    cli/
```

## ASDF 调整策略

### 阶段 A：纯移动时保留原始顺序

当前文件加载顺序跨越多个目标目录，例如 foundation JSON 与 protocol genesis、
storage 与 protocol validation、runtime 与 application bridge 都存在交错。把新目录立刻
包装成顶层 `:serial t` module 会实际重排编译顺序，不属于纯移动。

因此第一阶段只在现有 `src` 串行组件的原位置增加 `:pathname`，完整保留重构前的
全局顺序。现有 EVM opcode 和 HTTP 子模块只调整父级 pathname。这样路径变化和加载
顺序变化可以独立验证、独立回滚。

### 阶段 B：单独建立逻辑 module DAG

完成所有纯移动并从空缓存验证后，再将 ASDF 收敛为这些逻辑组件：

1. `packages`；
2. `foundation`；
3. `protocol`；
4. `runtime-core` 与 `storage-core`；
5. `application-services`；
6. `persistence-adapters` 与 `api`；
7. `transport`；
8. `app`。

顶层使用明确的 `:depends-on`；模块内部仍可保留 `:serial t`。该阶段必须单独做 cold
compile，因为它会首次改变既有全局文件顺序。

## 执行顺序

### 0. 保护栏

1. 从最新 `origin/main` 建立独立 worktree 分支；
2. 确认工作树不包含其他功能修改；
3. 建立 ASDF production source coverage 测试，要求每个 `src/**/*.lisp` 恰好出现一次；
4. 运行 package dependency DAG、source reference 和 symbol ownership 门禁；
5. 记录最新 main 的已有测试失败。

### 1. 生成完整映射

1. 按每个文件首个 `(in-package ...)` 核对 owner；
2. 对 bridge/service 例外逐项分类；
3. 检查 old path 和 new path 都无重复；
4. 检查映射集合与 `src/**/*.lisp` 完全相等。

### 2. 纯移动

按下面的可验证切片执行，每个切片只移动文件并替换 ASDF pathname：

1. package declarations、foundation、protocol；
2. runtime-core、storage-core、application services、persistence adapters；
3. API、HTTP transport、CLI app。

每个切片后执行 cold ASDF load 和四项架构门禁。全部移动后逐文件比较 Git blob，保证
新文件内容与旧文件内容完全相同。

### 3. 文档与完整验证

1. 更新 source ownership map；
2. 运行完整 unit suite；
3. 运行 integration 和 e2e；
4. 将 main 上可复现的失败与本次新增回归分开报告。

### 4. ASDF 模块依赖收紧

这一阶段与纯移动保持独立。先在临时分支或独立提交中重排逻辑 module，随后从空缓存
编译 production/test system，并重复完整测试。若出现隐含 compile-time 依赖，先记录并
修正依赖表达，不把兼容性改写混入移动变更。

### 5. 过度拆分审核

只在文件属于同一 package、没有独立公开契约、修改生命周期高度一致，并且合并后仍有
单一责任时才合并。600 行是建议阈值，1,200 行只是需要额外审查的经验上限，不是机械
验收规则。

交易 envelope、密码学算法、block header/body/root/receipt validation、EVM opcode family、
大型 precompile，以及 persistence 的不同记录类型不应合并。

## 验证策略

### 每个纯移动切片

- 从空缓存加载 `ethereum-lisp`；
- 验证 production ASDF source coverage；
- 验证 package dependency graph 无环；
- 验证源码引用被 dependency graph 覆盖；
- 验证 domain package 的 external symbols 由自身拥有；
- 比较旧 Git blob 与新工作树文件 hash。

### 全部纯移动后

```text
make docker-test-unit
make docker-test-integration
make docker-test-e2e
```

如果环境和资源允许，可改用 `make docker-test-all`。EEST fixture 不存在、SBCL 可选能力
或本地 socket 权限导致的 skip 应明确列出，不能默认为通过或回归。

## 本次执行基线（2026-07-15）

- 同步起点：`origin/main` commit `67bab05a8743445d698a7c266967c8897a2c2341`；
- production 源文件：304 个；
- 完整 unit：728 passed、3 skipped、3 failed；
- 以下 3 个失败可在未重构的同一 main commit 上独立复现，因此是已知基线，不是路径
  迁移回归：
  - `ENGINE-RPC-FORKCHOICE-UPDATED-V4-PREPARES-AMSTERDAM-PAYLOAD-V6`；
  - `RPC-HTTP-PACKAGE-BOUNDARY`；
  - `PRAGUE-BLOCK-DERIVES-ALL-EXECUTION-REQUEST-TYPES`。
- 完整 integration：232 passed、2 skipped、1 failed；失败的
  `DEVNET-CLI-DEV-PERIOD-TICK-CARRIES-ACTIVE-FORK-BODIES` 也可在同一 main commit 上
  精准复现，属于同一类 execution-requests hash 基线问题。
- 完整 e2e：56 passed、3 failed；以下 3 个失败均可在同一 main commit 上精准复现：
  - `DEVNET-SMOKE-GATE-SCRIPT-ENGINE-ONLY-SERVE-MODE`；
  - `PHASE-A-SMOKE-GATE-SCRIPT-CAN-INCLUDE-DEVNET-SUITE`；
  - `PHASE-A-SMOKE-GATE-DEVNET-MODE-IS-CWD-INDEPENDENT`。
  首个失败报告 KZG opt-in `engine_forkchoiceUpdatedV3` status mismatch，后两项是包含该
  smoke gate 的上层场景失败。
- ASDF 收紧后共有 10 个显式逻辑 module、304 个 production source component；cold
  coverage 和 module dependency edge 测试通过，unit、integration、e2e 的结果与上述
  基线保持一致。

## 完成标准

- `src/` 根目录不再包含领域实现 `.lisp` 文件；
- 304 个 production 文件全部且仅移动一次，内容 hash 不变；
- package 名、external symbols、symbol ownership 和 facade 不变；
- production ASDF 恰好覆盖每个源码文件一次，并能从空缓存加载；
- package dependency graph 保持无环，低层不依赖 RPC、HTTP 或 CLI；
- unit、integration、e2e 均通过，或失败已证明可在同步基线复现；
- 架构文档中的 source ownership map 使用新路径；
- ASDF module DAG 与纯移动分开验证；小文件合并继续作为后续独立变更。

## 回滚与提交边界

- 纯移动不包含函数重命名、抽象提取或功能修复；
- ASDF 依赖收紧与文件移动分开；
- 小文件合并与路径移动分开；
- 任一阶段出现新回归时，只回滚该阶段，不把风险累积到下一阶段。
