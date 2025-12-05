using KeraLua;
using Newtonsoft.Json;
using NLua;
using NLua.Exceptions;
using System;
using System.Collections.Generic;
using System.Diagnostics;
using System.Globalization;
using System.IO;
using System.Linq;
using System.Text;
using Lua = NLua.Lua;
using LuaFunction = NLua.LuaFunction;

namespace LayoutingTester
{
    public class TestLayout
    {
        public LayoutResult Result { get; } = new LayoutResult();
        public PlannerInput PlannerInput { get; }

        public StringBuilder textOutputBuilder = new StringBuilder();
        public string TextualFeedback => textOutputBuilder.ToString();

        public DateTime startTime = DateTime.UtcNow;
        public Stopwatch stopwatch;

        public bool PlanBeacons { get; }
        public bool PlanHeatPipes { get; }
        public bool PlanPowerPoles { get; }

        public TestLayout(string plannerInputAsJson, bool planBeacons = true, bool planHeatPipes = true, bool planPowerPoles = true)
        {
            PlanBeacons = planBeacons;
            PlanHeatPipes = planHeatPipes;
            PlanPowerPoles = planPowerPoles;

            PlannerInput = JsonConvert.DeserializeObject<PlannerInput>(plannerInputAsJson);
            Result.Columns = PlannerInput.ToColumns();
            RunLua();
            Print(DateTime.Now);
        }

        public void Print(object message)
        {
            if (message == null)
                textOutputBuilder.AppendLine("null");
            else if (message is LuaTable t)
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

        public void Lap(object message)
        {
            Print($"{stopwatch.ElapsedMilliseconds}ms -- {message}");
        }

        public long SampleStart()
        {
            return stopwatch.ElapsedTicks;
        }

        Dictionary<string, (long ticks, long count)> Samples = new();

        public void SampleFinish(string key, long start)
        {
            var accumulation = Samples.GetValueOrDefault(key, (0, 0));
            accumulation.count++;
            accumulation.ticks += stopwatch.ElapsedTicks - start;
            Samples[key] = accumulation;
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
                string solutionRoot = Environment.CurrentDirectory;
                while (solutionRoot is not null)
                {
                    if (Directory.EnumerateFiles(solutionRoot, "LICENSE").Any())
                    {
                        break;
                    }

                    solutionRoot = Path.GetDirectoryName(solutionRoot);
                }

                if (solutionRoot is null)
                {
                    throw new InvalidOperationException("The solution root could not be found.");
                }

                string[] factorioDirs = new[]
                {
                    Path.Combine(solutionRoot, "..", "factorio-data"),
                    Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.ProgramFilesX86), "Steam", "steamapps", "common", "Factorio", "data"),
                    Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.ProgramFilesX86), "Factorio"),
                    Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.ProgramFiles), "Steam", "steamapps", "common", "Factorio", "data"),
                    Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.ProgramFiles), "Factorio"),
                };

                string factorioDir = null;
                foreach (var candidate in factorioDirs)
                {
                    if (Directory.Exists(candidate))
                    {
                        factorioDir = Path.GetFullPath(candidate);
                        break;
                    }
                }

                if (factorioDir is null)
                {
                    throw new InvalidOperationException("The Factorio data directory could not be found.");
                }

                lua.NewTable("pumpdebug");
                lua.RegisterFunction("log", this, GetType().GetMethod(nameof(Print)));
                lua.RegisterFunction("pumpdebug.log", this, GetType().GetMethod(nameof(Print)));
                lua.RegisterFunction("pumpdebug.lap", this, GetType().GetMethod(nameof(Lap)));
                lua.RegisterFunction("pumpdebug.sample_start", this, GetType().GetMethod(nameof(SampleStart)));
                lua.RegisterFunction("pumpdebug.sample_finish", this, GetType().GetMethod(nameof(SampleFinish)));

                lua.NewTable("defines");
                lua.DoString(@"defines['direction'] = 
{
north=0, 
northnortheast=1, 
northeast=2, 
eastnortheast=3, 
east=4, 
eastsoutheast=5, 
southeast=6, 
southsoutheast=7, 
south=8, 
southsouthwest=9, 
southwest=10, 
westsouthwest=11, 
west=12, 
westnorthwest=13, 
northwest=14,  
northnorthwest=15
}
");

                var existingPath = lua["package.path"];
                existingPath += $";{solutionRoot}\\mod\\?.lua";
                existingPath += $";{factorioDir}\\base\\?.lua";
                existingPath += $";{factorioDir}\\core\\?.lua";
                existingPath += $";{factorioDir}\\core\\lualib\\?.lua";
                lua["package.path"] = existingPath;

                lua.DoString("require 'util'");
                lua.DoString("require 'math2d'");

                lua.DoString("require 'plib'");
                lua.DoString("require 'prospector'");
                lua.DoString("require 'toolbox'");
                lua.DoString("require 'toolshop'");
                lua.DoString("require 'plumber-pro'");
                lua.DoString("require 'electrician'");
                lua.DoString("heater = require 'heater'");
                lua.DoString("beaconer = require 'beaconer'");
                lua.DoString("require 'prospector'");

                lua.NewTable("planner_input_stage");
                var plannerInput = lua["planner_input_stage"] as LuaTable;
                lua.DoString(@"planner_input_stage.warnings = {}");
                PlannerInput.AddToTable(lua, plannerInput);
                var populateBlockedPositionsFunction = lua["populate_blocked_positions_from_area"] as LuaFunction;
                populateBlockedPositionsFunction.Call(plannerInput);

                var toolboxFunction = lua["add_development_toolbox"] as LuaFunction;
                toolboxFunction.Call(plannerInput);

                var toolbox = plannerInput.GetSubTable("toolbox");
                Result.ExtractorBoundingBox = BoundingBox.Read(toolbox.GetSubTable("extractor", "relative_bounds"));                
                Result.BeaconBoundingBox = BoundingBox.Read(toolbox.GetSubTable("beacon", "relative_bounds"));

                stopwatch = Stopwatch.StartNew();
                var plumberFunction = lua["plan_plumbing_pro"] as LuaFunction;
                plumberFunction.Call(plannerInput)?.FirstOrDefault();
                var plumberDuration = stopwatch.ElapsedMilliseconds;

                long beaconerDuration = 0;
                long heaterDuration = 0;
                long electricianDuration = 0;
                object heaterFailure = null;
                object electricianFailure = null;

                if (PlanBeacons)
                {
                    stopwatch.Restart();
                    var beaconerTable = (LuaTable)lua["beaconer"];
                    var planBeaconsFunction = (LuaFunction)beaconerTable["plan_beacons"];
                    planBeaconsFunction.Call(plannerInput);
                    beaconerDuration = stopwatch.ElapsedMilliseconds;
                }

                if (PlanHeatPipes)
                {
                    stopwatch.Restart();
                    var heaterTable = (LuaTable)lua["heater"];
                    var planHeatPipesFunction = (LuaFunction)heaterTable["plan_heat_pipes"];
                    heaterFailure = planHeatPipesFunction?.Call(plannerInput, null) ?? plannerInput["failure"];
                    heaterDuration = stopwatch.ElapsedMilliseconds;
                }

                if (PlanPowerPoles)
                {
                    stopwatch.Restart();
                    var electricianFunction = lua["plan_power"] as LuaFunction;
                    electricianFailure = electricianFunction.Call(plannerInput)?.FirstOrDefault() ?? plannerInput["failure"];
                    electricianDuration = stopwatch.ElapsedMilliseconds;
                }
                stopwatch.Restart();

                stopwatch.Stop();
                Print("---");
                Print($"'plumbing' took {plumberDuration}ms");
                Print($"'electricity' took {electricianDuration}ms");
                Print($"'heating' took {heaterDuration}ms");
                Print($"'beaconing' took {beaconerDuration}ms");
                Print("---");

                foreach (var kv in Samples.Select(x => x).OrderByDescending(x => x.Value.ticks))
                {
                    Print($"{TimeSpan.FromTicks(kv.Value.ticks).TotalMilliseconds}ms | {kv.Value.count} samples | {kv.Key}");
                }

                if (plannerInput["failure"] != null)
                    Print(plannerInput["failure"]);

                Print(lua["planner_input_stage.warnings"]);

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

            if ((DateTime.UtcNow - startTime).TotalSeconds > 5)
            {
                // ((Lua)sender).State.Error("Cancelled after 5 sec");
            }
        }

        private void AddConstructEntities(LuaTable constructionParameters)
        {
            if (constructionParameters == null) return;
            var totalPlannedEntities = 0;

            var left = PlannerInput.AreaBoundsFromJson.LeftTop.X;
            var top = PlannerInput.AreaBoundsFromJson.LeftTop.Y;
            var right = PlannerInput.AreaBoundsFromJson.RightBottom.X;
            var bottom = PlannerInput.AreaBoundsFromJson.RightBottom.Y;

            foreach (var xKey in constructionParameters.Keys)
            {
                var x = (double)xKey;
                var tableY = (LuaTable)constructionParameters[xKey];

                foreach (var yKey in tableY.Keys)
                {

                    var plannedEntity = (LuaTable)tableY[yKey];
                    var y = (double)yKey;
                    var name = (string)plannedEntity["name"];

                    if (x < left || x > right || y < top || y > bottom)
                    {
                        Print($"Entity planned out of bounds: {name} at x={x},y={y}");
                        continue;
                    }

                    Result.Columns[(float)x].AddConstructionResult(name, y, plannedEntity);
                    totalPlannedEntities++;
                }
            }

            Print($"Planned entities: {totalPlannedEntities}");
        }
    }

    public class TestLayoutColumn
    {
        public Dictionary<float, TestLayoutCell> Cells { get; }
        public float X { get; }

        public TestLayoutColumn(string x, TestLayoutCell[] cells)
        {
            X = float.Parse(x, CultureInfo.InvariantCulture);
            Cells = cells.ToDictionary(c => c.Y);
        }

        public void AddConstructionResult(string name, double y, LuaTable plannedEntity)
        {
            Cells[(float)y].AddConstructionResult(name, plannedEntity);
        }
    }

    public class TestLayoutCell
    {
        public string Content { get; private set; }
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
                Content = "pipe";
            }
            else if (name == "output")
            {
                EntityToConstruct = "o";
                Content = "pipe";
            }
            else if (name == "extractor")
            {
                EntityToConstruct = "p";
            }
            else if (name == "pipe_joint")
            {
                EntityToConstruct = "x";
                Content = "pipe";
            }
            else if (name == "pipe_tunnel")
            {
                EntityToConstruct = "t";
                Content = "pipe";
            }
            else if (name == "power_pole")
            {
                var placementOrder = (long)plannedEntity["placement_order"];
                EntityToConstruct = placementOrder.ToString();
                Content = "power_pole";
            }
            else if (name == "beacon")
            {
                EntityToConstruct = "B";
                Content = "beacon";
            }
            else if (name == "heat-pipe")
            {
                EntityToConstruct = plannedEntity["placement_order"].ToString();
                Content = "heat-pipe";
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

        public Dictionary<float, TestLayoutColumn> ToColumns()
        {
            return AreaFromJson
                .ToDictionary(
                    x_reservations => float.Parse(x_reservations.Key, CultureInfo.InvariantCulture),
                    x_reservations => new TestLayoutColumn(
                        x_reservations.Key,
                        x_reservations.Value
                            .Select(y_reservation => new TestLayoutCell(x_reservations.Key, y_reservation.Key, y_reservation.Value))
                            .ToArray()
                    )
                );
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

        public static BoundingBox Read(LuaTable table)
        {
            return new()
            {
                LeftTop = Position.Read((LuaTable)table["left_top"]),
                RightBottom = Position.Read((LuaTable)table["right_bottom"]),
            };
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

        public static Position Read(LuaTable table)
        {
            return new()
            {
                X = IntOrDouble(table["x"]),
                Y = IntOrDouble(table["y"]),
            };
        }

        private static double IntOrDouble(object intOrDouble)
        {
            if (intOrDouble is long l)
                return l;

            if (intOrDouble is double d)
                return d;

            throw new InvalidOperationException($"{intOrDouble.GetType().Name} is not an int64/long or a double");
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

        public static LuaTable GetSubTable(this LuaTable outerTable, params string[] path)
        {
            var subTable = (LuaTable)outerTable[path[0]];
            if (path.Length > 1)
                subTable = GetSubTable(subTable, path.Skip(1).ToArray());

            return subTable;
        }
    }
}