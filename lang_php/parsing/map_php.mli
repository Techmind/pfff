(*s: map_php.mli *)
open Ast_php
(* hooks *)
type visitor_in = {
  kexpr: (expr  -> expr) * visitor_out -> expr  -> expr;
  klvalue: (lvalue  -> lvalue) * visitor_out -> lvalue  -> lvalue;
  kstmt_and_def: 
   (stmt_and_def -> stmt_and_def) * visitor_out -> stmt_and_def ->stmt_and_def;
  kstmt: (stmt -> stmt) * visitor_out -> stmt -> stmt;
  kqualifier: (qualifier -> qualifier) * visitor_out -> qualifier -> qualifier;
  kclass_name_or_kwd: 
    (class_name_or_kwd -> class_name_or_kwd) * visitor_out -> 
     class_name_or_kwd -> class_name_or_kwd;
  kclass_def:  (class_def -> class_def) * visitor_out -> class_def -> class_def;
  knamespace_def:  (namespace_def -> namespace_def) * visitor_out -> namespace_def -> namespace_def;
  kinfo: (tok -> tok) * visitor_out -> tok -> tok;
                                                                            
}
and visitor_out = {
  vtop: toplevel -> toplevel;
  vstmt_and_def: stmt_and_def -> stmt_and_def;
  vprogram: program -> program;
  vexpr: expr -> expr;
  vlvalue: lvalue -> lvalue;
  vxhpattrvalue: xhp_attr_value -> xhp_attr_value;
  vany: any -> any;
}

val default_visitor: visitor_in
val mk_visitor: visitor_in -> visitor_out

(*e: map_php.mli *)
