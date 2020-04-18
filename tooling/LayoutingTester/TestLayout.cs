using System;
using System.Collections.Generic;
using System.Linq;
using System.Text;
using KeraLua;
using Newtonsoft.Json;
using NLua;
using NLua.Exceptions;
using Lua = NLua.Lua;
using LuaFunction = NLua.LuaFunction;

namespace LayoutingTester
{
    public class TestLayout
    {
        public TestLayoutColumn[] Columns { get; }
        public PlannerInput PlannerInput { get; }

        public StringBuilder textOutputBuilder = new StringBuilder();
        public string TextualFeedback => textOutputBuilder.ToString();

        public TestLayout(string plannerInputAsJson)
        {
            PlannerInput = JsonConvert.DeserializeObject<PlannerInput>(plannerInputAsJson);
            Columns = PlannerInput.ToColumns();

            RunLua();

            Print(DateTime.Now);
        }

        public void Print(object message)
        {
            if (message is LuaTable t)
            {
                textOutputBuilder.AppendLine("---");
                PrintTable(t);
            }
            else
            {
                var m = message.ToString();
                textOutputBuilder.AppendLine(message.ToString());
                if (m.Equals("Trace", StringComparison.OrdinalIgnoreCase))
                {
                    textOutputBuilder.AppendLine(lua.GetDebugTraceback());
                }
            }
        }

        public void PrintTable(LuaTable table, string prefix = "")
        {
            foreach (var key in table.Keys)
            {
                if (table[key] is LuaTable subTable)
                {
                    PrintTable(subTable, $"{prefix}[{key}]");
                }
                else
                {
                    textOutputBuilder
                        .Append(prefix)
                        .AppendLine($"[{key}]={table[key]}");
                }
            }
        }

        public void RunLua()
        {
            lua = new Lua();
            //lua.SetDebugHook(LuaHookMask.Line, 1);
            lua.DebugHook += Lua_DebugHook;
            try
            {

                // Arrange
                lua.NewTable("pumpdebug");
                lua.RegisterFunction("pumpdebug.log", this, GetType().GetMethod(nameof(Print)));
                lua.DoFile("../../../../../mod/planner.lua");
                lua.NewTable("defines");
                lua.DoString("defines['direction'] = {north=0, east=2, south=4, west=6}");
                lua.NewTable("planner_input_stage");
                var plannerInputTable = lua["planner_input_stage"] as LuaTable;
                PlannerInput.AddToTable(lua, plannerInputTable);

                // Act
                var plannerInput = lua["planner_input_stage"];
                var planFunction = lua["plan"] as LuaFunction;
                var planResult = planFunction.Call(plannerInput);

                // Extract result
                var constructEntities = planResult.First() as LuaTable;
                var pumpjacks = constructEntities["pumpjack"] as LuaTable;
                var pipes = constructEntities["pipe"] as LuaTable;

                foreach (LuaTable pumpjack in pumpjacks.Values)
                {
                    AddConstructEntity("pumpjack", pumpjack);
                }

                foreach (LuaTable pipe in pipes.Values)
                {
                    AddConstructEntity("pipe", pipe);
                }
            }
            catch (LuaScriptException e)
            {
                var traceBack = lua.GetDebugTraceback();
                textOutputBuilder.AppendLine(e.ToString());
                if (lastStack != null)
                {
                    textOutputBuilder.AppendLine(lastStack);
                }
            }
            catch (Exception e)
            {
                Print("Shite output somewhere, because an exception occurred when adding the output to the visualization.");
                Print(e);
            }
            finally
            {
                lua = null;
            }

        }

        private Lua lua;
        private string lastStack = null;

        private void Lua_DebugHook(object sender, NLua.Event.DebugHookEventArgs e)
        {
            if (e.LuaDebug.Event == LuaHookEvent.Line && e.LuaDebug.CurrentLine == 294)
            {
                lastStack = lua.GetDebugTraceback();
            }
        }

        private void AddConstructEntity(string entityName, LuaTable constructionParameters)
        {
            LuaTable position = constructionParameters["position"] as LuaTable;
            var x = (double)position["x"];
            var y = (double)position["y"];
            var direction = (long)constructionParameters["direction"];

            Columns.First(c => c.X == x).AddConstructionResult(entityName, y, direction);
        }
    }

    public class TestLayoutColumn
    {
        public TestLayoutCell[] Cells { get; }
        public float X { get; }

        public TestLayoutColumn(string x, TestLayoutCell[] cells)
        {
            X = float.Parse(x);
            Cells = cells;
        }

        public void AddConstructionResult(string name, double y, long direction)
        {
            Cells.First(c => c.Y == y).AddConstructionResult(name, direction, X);
        }
    }

    public class TestLayoutCell
    {
        public string Content { get; }
        public float Y { get; }

        public string EntityToConstruct { get; private set; }
        public long EntityToConstructDirection { get; private set; } = -1;

        public TestLayoutCell(string y, string content)
        {
            Y = float.Parse(y);
            Content = content;
        }

        public void AddConstructionResult(string name, long direction, float x)
        {
            if (EntityToConstruct != null)
            {
                throw new ArgumentException($"Can't add {name} at position x={x},y={Y}. A {EntityToConstruct} is already assigned here.");
            }

            if (name == "pipe")
            {
                EntityToConstruct = "+";
            }
            else if (name == "pumpjack")
            {
                EntityToConstruct = "p";
            }

            EntityToConstructDirection = direction;
        }
    }

    public class PlannerInput
    {
        [JsonProperty("area")]
        public Dictionary<string, Dictionary<string, string>> AreaFromJson { get; set; }

        [JsonProperty("area_bounds")]
        public BoundingBox AreaBoundsFromJson { get; set; }

        public TestLayoutColumn[] ToColumns()
        {
            return AreaFromJson
                .Select(
                    x_reservations => new TestLayoutColumn(x_reservations.Key, x_reservations.Value
                        .Select(y_reservation => new TestLayoutCell(y_reservation.Key, y_reservation.Value))
                        .ToArray()))
                .ToArray();
        }

        public void AddToTable(Lua lua, LuaTable table)
        {
            var areaBoundsTable = LuaHelper.AddSubTable(lua, table, "area_bounds");
            AreaBoundsFromJson.AddToTable(lua, areaBoundsTable);

            var areaTable = LuaHelper.AddSubTable(lua, table, "area");
            foreach (var column in AreaFromJson)
            {
                var columnTable = areaTable.AddSubTable(lua, double.Parse(column.Key));
                foreach (var cell in column.Value)
                {
                    columnTable[double.Parse(cell.Key)] = cell.Value;
                }
            }
        }
    }

    public class BoundingBox
    {
        [JsonProperty("left_top")]
        public Position LeftTop { get; set; }

        [JsonProperty("right_bottom")]
        public Position RightBottom { get; set; }

        public void AddToTable(Lua lua, LuaTable table)
        {
            var leftTopTable = LuaHelper.AddSubTable(lua, table, "left_top");
            LeftTop.AddToTable(lua, leftTopTable);
            var rightBottomTable = LuaHelper.AddSubTable(lua, table, "right_bottom");
            RightBottom.AddToTable(lua, rightBottomTable);
        }
    }

    public class Position
    {
        [JsonProperty("x")]
        public double X { get; set; }

        [JsonProperty("y")]
        public double Y { get; set; }

        public void AddToTable(Lua lua, LuaTable table)
        {
            table["x"] = X;
            table["y"] = Y;
        }
    }

    public static class LuaHelper
    {
        public static LuaTable AddSubTable(Lua lua, LuaTable outerTable, object key)
        {
            var createTableResult = lua.DoString("return {}").First();
            outerTable[key] = createTableResult;
            var newTableAsObject = outerTable[key];
            var newTable = newTableAsObject as LuaTable;
            return newTable;
        }

        public static LuaTable AddSubTable(this LuaTable outerTable, Lua lua, object key)
        {
            return AddSubTable(lua, outerTable, key);
        }
    }
}