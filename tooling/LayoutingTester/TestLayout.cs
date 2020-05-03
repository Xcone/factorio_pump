using System;
using System.Collections.Generic;
using System.IO;
using System.Linq;
using System.Text;
using KeraLua;
using Microsoft.VisualBasic.CompilerServices;
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
                
                string solutionRoot = Environment.CurrentDirectory + "\\..\\..\\..\\..\\..\\";
                string factorioDir = $"{solutionRoot}..\\factorio-data\\";
                lua.NewTable("pumpdebug");
                lua.RegisterFunction("pumpdebug.log", this, GetType().GetMethod(nameof(Print)));

                var existingPath = lua["package.path"];
                existingPath += $";{solutionRoot}mod\\?.lua";
                existingPath += $";{factorioDir}base\\?.lua";
                existingPath += $";{factorioDir}core\\?.lua";
                existingPath += $";{factorioDir}core\\lualib\\?.lua";
                lua["package.path"] = existingPath;

                lua.DoString("require 'util'");
                lua.DoString("require 'math2d'");

                lua.NewTable("defines");
                lua.DoString("defines['direction'] = {north=0, east=2, south=4, west=6}");

                lua.DoString("require 'helpers'");
                lua.DoString("require 'toolbox'");
                lua.DoString("require 'planner'");


                lua.NewTable("planner_input_stage");
                var plannerInput = lua["planner_input_stage"] as LuaTable;
                PlannerInput.AddToTable(lua, plannerInput);

                var toolboxFunction = lua["add_development_toolbox"] as LuaFunction;
                toolboxFunction.Call(plannerInput);

                // Act
                var planFunction = lua["add_construction_plan"] as LuaFunction;
                var failure = planFunction.Call(plannerInput)?.First();

                // Extract result
                if (failure != null)
                {
                    Print(failure);
                }

                var constructEntities = lua["planner_input_stage.construction_plan"] as LuaTable;
                var pumpjacks = constructEntities["extractors"] as LuaTable;
                var outputs = constructEntities["outputs"] as LuaTable;
                var pipes = constructEntities["connectors"] as LuaTable;
                var pipeJoints = constructEntities["connector_joints"] as LuaTable;
                var pipesToGround = constructEntities["connectors_underground"] as LuaTable;

                foreach (LuaTable pumpjack in pumpjacks.Values)
                {
                    AddConstructEntity("pumpjack", pumpjack);
                }

                foreach (LuaTable output in outputs.Values)
                {
                    AddConstructEntity("output", output);
                }

                foreach (LuaTable pipe in pipes.Values)
                {
                    AddConstructEntity("pipe", pipe);
                }

                foreach (LuaTable pipeToGround in pipesToGround.Values)
                {
                    AddConstructEntity("pipe-to-ground", pipeToGround);
                }

                foreach (LuaTable pipeJoint in pipeJoints.Values)
                {
                    AddConstructEntity("pipe_joint", pipeJoint);
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
        public float X { get; }
        public float Y { get; }

        public string EntityToConstruct { get; private set; }
        public long EntityToConstructDirection { get; private set; } = -1;

        public TestLayoutCell(string x, string y, string content)
        {
            X = float.Parse(x);
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
            else if (name == "output")
            {
                EntityToConstruct = "o";
            }
            else if (name == "pumpjack")
            {
                EntityToConstruct = "p";
            }
            else if (name == "pipe_joint")
            {
                EntityToConstruct = "x";
            }
            else if (name == "pipe-to-ground")
            {
                EntityToConstruct = "t";
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
                        .Select(y_reservation => new TestLayoutCell(x_reservations.Key, y_reservation.Key, y_reservation.Value))
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