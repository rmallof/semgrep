(*s: semgrep/matching/SubAST_generic.ml *)
(*s: pad/r2c copyright *)
(* Yoann Padioleau
 *
 * Copyright (C) 2019-2020 r2c
 *
 * This library is free software; you can redistribute it and/or
 * modify it under the terms of the GNU Lesser General Public License
 * version 2.1 as published by the Free Software Foundation, with the
 * special exception on linking described in file license.txt.
 *
 * This library is distributed in the hope that it will be useful, but
 * WITHOUT ANY WARRANTY; without even the implied warranty of
 * MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the file
 * license.txt for more details.
 *)
(*e: pad/r2c copyright *)

open AST_generic
module V = Visitor_AST

(*****************************************************************************)
(* Prelude *)
(*****************************************************************************)
(* Various helper functions to extract subparts of AST elements.
 *
 *)

(*****************************************************************************)
(* Expressions *)
(*****************************************************************************)

(*s: function [[SubAST_generic.subexprs_of_expr]] *)
(* used for deep expression matching *)
let subexprs_of_expr2 e =
  match e with
  | L _
  | Id _ | IdQualified _  | IdSpecial _
  | Ellipsis _ | TypedMetavar _
    -> []

  | DotAccess (e, _, _) | Await (_, e) | Cast (_, e)
  | Ref (_, e) | DeRef (_, e) | DeepEllipsis (_, e, _)
    -> [e]
  | Assign (e1, _, e2) | AssignOp (e1, _, e2)
  | ArrayAccess (e1, e2)
    (* not sure we always want to return 'e1' here *)
    -> [e1;e2]
  | Conditional (e1, e2, e3)
    -> [e1;e2;e3]
  | Tuple xs | Seq xs
    -> xs
  | Container (_, xs)
    -> unbracket xs


  | Call (e, args) ->
      (* not sure we want to return 'e' here *)
      e::
      (args |> Common.map_filter (function
        | Arg e | ArgKwd (_, e) -> Some e
        | ArgType _ | ArgOther _ -> None
      ))
  | SliceAccess (e1, e2opt, e3opt, e4opt) ->
      e1::([e2opt;e3opt;e4opt] |> List.map Common.opt_to_list |> List.flatten)
  | Yield (_, eopt, _) -> Common.opt_to_list eopt
  | OtherExpr (_, anys) ->
      (* in theory we should go deeper in any *)
      anys |> Common.map_filter (function
        | E e -> Some e
        | _ -> None
      )

  (* currently skipped over but could recurse *)
  | Record _
  | Constructor _
  | Lambda _
  | AnonClass _
  | Xml _
  | LetPattern _ | MatchPattern _
    -> []
  | DisjExpr _ -> raise Common.Impossible
(*e: function [[SubAST_generic.subexprs_of_expr]] *)
let subexprs_of_expr a = Common.profile_code "Sub.subexprs_of_expr" (fun () ->
      subexprs_of_expr2 a)

(*****************************************************************************)
(* Statements *)
(*****************************************************************************)

(*s: function [[SubAST_generic.subexprs_of_stmt]] *)
(* used for really deep statement matching *)
let subexprs_of_stmt st =
    match st with
    (* 1 *)
    | ExprStmt e
    | If (_, e, _, _)
    | While (_, e, _)
    | DoWhile (_, _, e)
    | DefStmt (_, VarDef { vinit = Some e; _ })
    | For (_, ForEach (_, _, e), _)
    | Continue (_, LDynamic e)
    | Break (_, LDynamic e)
    | Throw (_, e)
    | OtherStmtWithStmt (_, e, _)
     -> [e]

    (* opt *)
    | Switch (_, eopt, _)
    | Return (_, eopt)
     -> Common.opt_to_list eopt

    (* n *)
    | For (_, ForClassic (xs, eopt1, eopt2), _) ->
      (xs |> Common.map_filter (function
       | ForInitExpr e -> Some e
       | ForInitVar (_, vdef) -> vdef.vinit
      )) @
      Common.opt_to_list eopt1 @
      Common.opt_to_list eopt2

    | Assert (_, e1, e2opt) ->
      e1::Common.opt_to_list e2opt

    (* 0 *)
    | DirectiveStmt _
    | Block _
    | Continue _ | Break _
    | Label _ | Goto _
    | Try _
    | DisjStmt _
    | DefStmt _
    (* could extract the expr in any? *)
    | OtherStmt _
     -> []
(*e: function [[SubAST_generic.subexprs_of_stmt]] *)

(*s: function [[SubAST_generic.substmts_of_stmt]] *)
(* used for deep statement matching *)
let substmts_of_stmt st =
    match st with
    (* 0 *)
    | DirectiveStmt _
    | ExprStmt _
    | Return _ | Continue _ | Break _ | Goto _
    | Throw _
    | Assert _
    | OtherStmt _
    -> []

    (* 1 *)
    | While (_, _, st) | DoWhile (_, st, _)
    | For (_, _, st)
    | Label (_, st)
    | OtherStmtWithStmt (_, _, st)
    -> [st]

    (* 2 *)
    | If (_, _, st1, st2)
    -> [st1; st2]

    (* n *)
    | Block xs ->
        xs
    | Switch (_, _, xs) ->
        xs |> List.map snd
    | Try (_, st, xs, opt) ->
        [st] @
        (xs |> List.map Common2.thd3) @
        (match opt with None -> [] | Some (_, st) -> [st])

    | DisjStmt _ -> raise Common.Impossible

    (* this may slow down things quite a bit *)
    | DefStmt (_ent, def) ->
       if not !Flag_semgrep.go_really_deeper_stmt
       then []
       else
         (match def with
         | VarDef _
         | TypeDef _
         | MacroDef _
         | Signature _
         | UseOuterDecl _
         (* recurse? *)
         | ModuleDef _
                -> []
         (* this will add lots of substatements *)
         | FuncDef def ->
            [def.fbody]
         | ClassDef def ->
            def.cbody |> unbracket |> Common.map_filter (function
              | FieldStmt st -> Some st
              | FieldDynamic _ | FieldSpread _ -> None
            )
         )
(*e: function [[SubAST_generic.substmts_of_stmt]] *)

(*****************************************************************************)
(* Visitors  *)
(*****************************************************************************)
(*s: function [[SubAST_generic.do_visit_with_ref]] *)
(* TODO: move in pfff at some point *)
let do_visit_with_ref mk_hooks = fun any ->
  let res = ref [] in
  let hooks = mk_hooks res in
  let vout = V.mk_visitor hooks in
  vout any;
  List.rev !res
(*e: function [[SubAST_generic.do_visit_with_ref]] *)

(*s: function [[SubAST_generic.lambdas_in_expr]] *)
let lambdas_in_expr2 e =
  do_visit_with_ref (fun aref -> { V.default_visitor with
    V.kexpr = (fun (k, _) e ->
      match e with
      | Lambda def -> Common.push def aref
      | _ -> k e
    );
  }) (E e)
(*e: function [[SubAST_generic.lambdas_in_expr]] *)
let lambdas_in_expr a = Common.profile_code "Sub.lambdas_in_expr" (fun () ->
      lambdas_in_expr2 a)

(* opti: using memoization speed things up a bit too
 * (but again, this is still slow when called many many times).
 * todo? note that this is not the optimal memoization we can do because
 * using Hashtbl where the key is a full expression can be slow (hashing
 * huge expressions still takes some time). It would be better to
 * return a unique identifier to each expression to remove the hashing cost.
 *)
let hmemo = Hashtbl.create 101
let lambdas_in_expr_memo2 a =
  Common.memoized hmemo a (fun () -> lambdas_in_expr a)
let lambdas_in_expr_memo a = Common.profile_code "Sub.lambdas_in_expr_memo"
 (fun () -> lambdas_in_expr_memo2 a)

(*****************************************************************************)
(* Really substmts_of_stmts *)
(*****************************************************************************)

(*s: function [[SubAST_generic.flatten_substmts_of_stmts]] *)
let flatten_substmts_of_stmts2 xs =
  (* opti: using a ref, List.iter, and Common.push instead of a mix of
   * List.map, List.flatten and @ below speed things up
   * (but it is still slow when called many many times)
   *)
  let res = ref [] in

  let rec aux x =
    (* return the current statement first, and add substmts *)
    Common.push x res;

    (* this can be really slow because lambdas_in_expr() below can be called
     * a zillion times on big files (see tests/PERF/) if we do the
     * matching naively in m_stmts_deep.
     *)
    (if not !Flag_semgrep.go_really_deeper_stmt
    then ()
    else begin
       let es = subexprs_of_stmt x in
       (* getting deeply nested lambdas stmts *)
       let lambdas = es |> List.map lambdas_in_expr_memo |> List.flatten in
       lambdas |> List.map (fun def -> def.fbody) |> List.iter aux
    end);

    let xs = substmts_of_stmt x in
    xs |> List.iter aux;
  in
  xs |> List.iter aux;
  List.rev !res
(*e: function [[SubAST_generic.flatten_substmts_of_stmts]] *)
let flatten_substmts_of_stmts a =
  Common.profile_code "Sub.flatten_substmts_of_stmts" (fun () ->
      flatten_substmts_of_stmts2 a)

(*e: semgrep/matching/SubAST_generic.ml *)