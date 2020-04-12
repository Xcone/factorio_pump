using System;
using System.Collections.Generic;
using System.Linq;
using Newtonsoft.Json;
using NLua;

namespace LayoutingTester
{
    public class TestLayout
    {
        public TestLayoutColumn[] Columns { get; }
        public PlannerInput PlannerInput { get; }

        public string TextualFeedback { get; private set; }

        public TestLayout(string plannerInputAsJson)
        {
            PlannerInput = JsonConvert.DeserializeObject<PlannerInput>(plannerInputAsJson);
            Columns = PlannerInput.ToColumns();

            RunLua();
        }

        public void RunLua()
        {
            try
            {
                // Arrange
                using var lua = new Lua();
                lua.DoFile("../../../../../mod/planner.lua");
                lua.NewTable("defines");
                lua.DoString("defines['direction'] = {north=0, east=2, south=4, west=6}");
                lua.NewTable("planner_input_stage");
                lua.NewTable("planner_input_stage.area");
                var areaTable = lua["planner_input_stage.area"] as LuaTable;
                
                foreach (var c in Columns)
                {
                    c.AddToTable(lua, areaTable);
                }

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
            catch (Exception e)
            {
                TextualFeedback = e.ToString();
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

        public void AddToTable(Lua lua, LuaTable table)
        {

            table[X] = lua.DoString("return {}").First();
            var tableXAsObject = table[X];
            var tableXAsTable = tableXAsObject as LuaTable;
            foreach (var cell in Cells)
            {
                cell.AddToTable(lua, tableXAsTable);
            }
        }

        public void AddConstructionResult(string name, double y, long direction)
        {
            Cells.First(c => c.Y == y).AddConstructionResult(name, direction);
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

        public void AddToTable(Lua lua, LuaTable table)
        {
            table[Y] = Content;
        }

        public void AddConstructionResult(string name, long direction)
        {
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

        public TestLayoutColumn[] ToColumns()
        {
            return AreaFromJson
                .Select(
                    x_reservations => new TestLayoutColumn(x_reservations.Key, x_reservations.Value
                        .Select(y_reservation => new TestLayoutCell(y_reservation.Key, y_reservation.Value))
                        .ToArray()))
                .ToArray();
        }
    }
}