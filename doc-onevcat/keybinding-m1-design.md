# M1 Keybinding Schema / Resolver / Migration 设计说明

关联 issue：#82（parent: #72）

## 目标

在不改动 UI 接线（M2+ 再做）的前提下，先把快捷键的数据模型稳定下来，提供一个可版本化、可迁移、可测试的统一入口。

本次交付新增三层：

1. **Schema（版本化）**
   - `KeybindingSchemaDocument`（含 `version`）
   - `KeybindingCommandSchema`（`id/title/scope/platform/allowUserOverride/conflictPolicy/defaultBinding`）
   - `Keybinding` + `KeybindingModifiers`

2. **Resolver（统一解析）**
   - 输入：`schema + userOverrides + migratedOverrides`
   - 输出：`ResolvedKeybindingMap`（`bindingsByCommandID`）
   - 解析优先级：`userOverride > migratedLegacy > appDefault`
   - 对 `allowUserOverride == false` 的命令，忽略覆盖输入，保持默认值。

3. **Migration（旧配置迁移）**
   - 提供 `LegacyCustomCommandShortcutMigration`，将旧 `UserCustomCommand.shortcut` 迁移为统一 override 结构。
   - 迁移目标 ID：`custom_command.<legacyCommandID>`。
   - 对无法映射项（空 command id / 非法 shortcut）不静默丢弃：写入 `issues`，并记录 warning log。

## 为什么这样拆

- M1 不直接侵入现有命令系统与 UI，避免一次改动面过大。
- 先把 **schema + resolver + migration contract** 固化，M2/M3/M4 才能在同一个数据源上接线。
- 迁移层单独可测，后续接入持久化时风险可控。

## 当前边界

- 暂未把新 resolver 接入菜单、command palette、Ghostty 参数和设置页面（这些属于后续里程碑）。
- 当前新增能力以模型与测试为主，保证后续接线时行为可预测。

## 测试覆盖

- schema encode/decode roundtrip + version 校验
- app 默认 schema 生成与关键字段校验
- resolver 合并优先级（含 system fixed 不可覆盖）
- legacy custom shortcut 迁移 + unmapped issue 收集
