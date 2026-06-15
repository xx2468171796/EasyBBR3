## 🔗 如何与中枢 ankottipublic 交互
本项目是中犇 ecosystem 的一员(**不是孤岛**)。中枢 = `ankottipublic`(标准/知识/关系图)+ ecosystem-hub(http://192.168.110.246:8771)。通过 **ecosystem MCP**(`mcp__ecosystem__*`)实时联动;缺 MCP 跑 `~/code/ankottipublic/scripts/setup-mcp.mjs`(见 `skills/onboard-machine`)。

- **开发前查复用**:`ecosystem_discover <需求>`(支付/数据库/密钥/备份…),别重造。本项目依赖:(无)。
- **查依赖/影响面**:`ecosystem_get <id>` / `ecosystem_graph`。
- **查踩坑**:`knowledge_search <关键词>`。
- **和 Codex 并行**:改文件前 `coord_claim` 防冲突,开工先 `coord_status`+`coord_read`;沉淀 `mem_add`(`project` 传本仓根绝对路径)。
- **上线能力/依赖变了** → `ecosystem_update easybbr3` 回写关系图,保持不分叉。
- **📣 汇报义务(必须)**:完成功能/修完 bug/部署/遇阻塞 → `report({project:"easybbr3", summary:"一句话进展"})` 报到中枢看板,老板实时看;别等人问。需要技能照做 `skill <名字>`,生图用 `imagegen`,派活给另一个 AI 用 `delegate`。
- 标准遵循 ankottipublic `rules/knowledge/skills`;push Gitea 自动镜像 GitHub。
