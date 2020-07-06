require("./config/config");

const { Todo } = require("./models/todos/todo");
const db = require("./db");

const app = {
  emit: function (msg) {
    console.log("Emitted: ", msg)
    Todo.deleteMany({}, (err, result) => {
      if (err != null) {
        console.log("Err: ", err, " Result ", result)
        process.exit(1)
      } else {
        console.log("Successfully deleted all todos!")
        process.exit(0)
      }
    })
  }
}

db.connect(app);


