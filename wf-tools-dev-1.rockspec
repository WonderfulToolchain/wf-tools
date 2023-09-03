package = "wf-tools"
version = "dev-1"
source = {
   url = "https://github.com/WonderfulToolchain/wf-tools"
}
dependencies = {
   "lua >= 5.4, <= 5.4"
}
build = {
   type = "builtin",
   modules = {
      ["wf.internal.native"] = {"src/lua/native.c"}
   }
}
