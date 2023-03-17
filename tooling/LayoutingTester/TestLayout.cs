using System;
using System.Collections.Generic;
using System.Globalization;
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
            CultureInfo.CurrentCulture = CultureInfo.InvariantCulture;
            
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
                lua.DoString("require 'plumber'");
                lua.DoString("require 'electrician'");


                lua.NewTable("planner_input_stage");
                var plannerInput = lua["planner_input_stage"] as LuaTable;
                PlannerInput.AddToTable(lua, plannerInput);

                var toolboxFunction = lua["add_development_toolbox"] as LuaFunction;
                toolboxFunction.Call(plannerInput);

                // Act
                var stopWatch = System.Diagnostics.Stopwatch.StartNew();

                var plumberFunction = lua["plan_plumbing"] as LuaFunction;
                var electricianFunction = lua["plan_power"] as LuaFunction;
                var plumberFailure = plumberFunction.Call(plannerInput)?.FirstOrDefault() ?? plannerInput["failure"];
                var electricianFailure = electricianFunction.Call(plannerInput)?.FirstOrDefault() ?? plannerInput["failure"];

                stopWatch.Stop();
                Print($"'add_construction_plan' took {stopWatch.ElapsedMilliseconds}ms");


                // Extract result
                if (plumberFailure != null)
                {
                    Print(plumberFailure);
                }
                if (electricianFailure != null)
                {
                    Print(electricianFailure);
                }

                var constructEntities = lua["planner_input_stage.construction_plan"] as LuaTable;
                AddConstructEntities(constructEntities);

                Print("---------------");
                Print("Result");
                Print("---------------");
                Print(constructEntities != null ? constructEntities : "Nothing ... ");
                
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

        private void AddConstructEntities(LuaTable constructionParameters)
        {
            if (constructionParameters == null) return;

            foreach (var xKey in constructionParameters.Keys)
            {
                var tableY = (LuaTable)constructionParameters[xKey];

                foreach (var yKey in tableY.Keys)
                {
                    var plannedEntity = (LuaTable)tableY[yKey];
                    var x = (double) xKey;
                    var y = (double) yKey;
                    var name = (string)plannedEntity["name"];                    

                    Columns.First(c => c.X == x).AddConstructionResult(name, y, plannedEntity);
                }
            }
        }
    }

    public class TestLayoutColumn
    {
        public TestLayoutCell[] Cells { get; }
        public float X { get; }

        public TestLayoutColumn(string x, TestLayoutCell[] cells)
        {
            X = float.Parse(x, CultureInfo.InvariantCulture);
            Cells = cells;
        }

        public void AddConstructionResult(string name, double y, LuaTable plannedEntity)
        {
            Cells.First(c => c.Y == y).AddConstructionResult(name, plannedEntity);
        }
    }

    public class TestLayoutCell
    {
        public string Content { get; private set;}
        public float X { get; }
        public float Y { get; }

        public string EntityToConstruct { get; private set; }
        public long EntityToConstructDirection { get; private set; } = -1;

        public TestLayoutCell(string x, string y, string content)
        {
            X = float.Parse(x, CultureInfo.InvariantCulture);
            Y = float.Parse(y, CultureInfo.InvariantCulture);
            Content = content;
        }

        public void AddConstructionResult(string name, LuaTable plannedEntity)
        {
            if (EntityToConstruct != null)
            {
                throw new ArgumentException($"Can't add {name} at position x={X},y={Y}. A {EntityToConstruct} is already assigned here.");
            }

            if (name == "pipe")
            {
                EntityToConstruct = "+";
            }
            else if (name == "output")
            {
                EntityToConstruct = "o";
            }
            else if (name == "extractor")
            {
                EntityToConstruct = "p";
            }
            else if (name == "pipe_joint")
            {
                EntityToConstruct = "x";
            }
            else if (name == "pipe_tunnel")
            {
                EntityToConstruct = "t";
            }
            else if (name == "power_pole")
            {
                var placementOrder = (long)plannedEntity["placement_order"];
                EntityToConstruct = placementOrder.ToString();
                Content = "power_pole";
            }

            var direction = (long)plannedEntity["direction"];
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