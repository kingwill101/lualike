import 'package:lualike/lualike.dart';

// void main() {
//   final doc = parse('''
// function add(a, b)
//    return a + b
// end
// ''');
//   print(doc);
//   print(doc.toSource());
// }

void main() {
  // main2();
  implicitSelf();
}

void implicitSelf() {
  final source = '''
        local obj = {}
        function obj:val(x)
          return x
        end
        local result = obj:val(99)
  ''';

  final res = parse(source);
  print(res);
}

void vararg() {
  final source = '''
  function sum(name, ...)
  end
  ''';

  final res = parse(source);
  print(res);
}

void main2() {
  final doc = parse('''
  
  a = 1;
if true then
  print("Hello, World!");
elseif false then
  print("This won't be printed.");print("This won't be printed.");
else
  print("This will be printed.")
end
''');
  print(doc);
}

keyassignment1() {
  final source = '''
  words[i] = 11
  ''';

  final res = parse(source);
  print(res);
}

keyassignment2() {
  final source = '''
  words[i] = 11
  words.something.value[i] = 11
  ''';

  final res = parse(source);
  print(res);
}

function() {
  final source = r'''
  print("Hello, World!")
 require"tracegc".start()
 table.property"first" 
 
-----------------------------------------      
 print("fdfasdfa sdfa sdf

 sss
 ")
 
  -----------------------------------------
 local a
do ;;; end
; do ; a = 3; assert(a == 3) end;
;

-----------------------------------------
if false then a = 3 // 0; a = 0 % 0 end
-----------------------------------------
local operator = {"+", "-", "*", "/", "//", "%", "^",
                    "&", "|", "^", "<<", ">>",
                    "==", "~=", "<", ">", "<=", ">=",}


-----------------------------------------
a = 'alo\n123"'
a = "alo\n123\""
a = '\97lo\10\04923"'
a = [[alo
123"]]
a = [==[
alo
123"]==]

-----------------------------------------

string.format([[return function (x,y)
                return x %s y
              end]], op)
              
   callFunctionWithFunctionReturn()();
              -----------------------------------------
              
  person = {}
  person.name = "Charlie"
  person["age"] = 35
  person.contact = {}
  person["contact"].email = "charlie@example.com"
  person.contact.phone = "555-1234"
          ''';

  final res = parse(source);
  print(res);
}
