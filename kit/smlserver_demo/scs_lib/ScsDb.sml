signature SCS_DB =
  sig
    val dbClickDml    : string -> string -> string -> string -> quot -> unit
    val dbClickDmlDb  : Db.Handle.db -> string -> string -> string -> string -> quot -> unit
    val panicDml      : quot -> unit
    val panicDmlTrans : (Db.Handle.db -> 'a) -> 'a
    val errorDml      : quot -> quot -> unit
    val toggleP       : string -> string -> string -> string -> unit

    val oneFieldErrPg : quot * quot -> string
    val oneRowErrPg'  : (((string -> string)->'a) * quot * quot) -> 'a
    val panicOneRow   : ((string->string)->'a) -> quot -> 'a
    val panicZeroOrOneRow : ((string->string)->'a) -> quot -> 'a option

    (* [userLang user_id] returns the language preference for user
       user_id formatted as a string that can be used when accessing
       Oracle. *)
    val userLang : int -> string

    val ppDate        : string -> string
  end

structure ScsDb :> SCS_DB =
  struct
    fun dbClickDml table_name id_column_name generated_id return_url insert_sql =
      (Db.dml insert_sql;
       Ns.returnRedirect return_url; Ns.exit())
      handle Fail s =>
	(if Db.existsOneRow `select 1 as num from ^table_name where ^id_column_name = '^(Db.qq generated_id)'` 
	   then (Ns.returnRedirect return_url; Ns.exit()) (* it's a double click, so just redirect the user to the index page *)
	 else ScsError.panic (`DbFunctor.dbClickDml choked. DB returned error on SQL ` ^^ insert_sql)
	   handle X => ScsError.panic (`DbFunctor.dbClickDml choked. DB returned error on SQL ` 
				       ^^ insert_sql ^^ `^(General.exnMessage X)`))

    fun dbClickDmlDb db table_name id_column_name generated_id return_url insert_sql =
      (Db.Handle.dmlDb db insert_sql;
       Ns.returnRedirect return_url;())
      handle Fail s =>
	(if Db.Handle.existsOneRowDb db `select 1 as num from ^table_name where ^id_column_name = '^(Db.qq generated_id)'` 
	   then (Ns.returnRedirect return_url;()) (* it's a double click, so just redirect the user to the index page *)
	 else raise Fail "DbFunctor.dbClickDml choked. DB returned error on SQL "
	   handle X => raise Fail "DbFunctor.dbClickDml choked. DB returned error on SQL")

    fun panicDml f = Db.panicDml ScsError.panic f
    fun panicDmlTrans f = Db.Handle.panicDmlTrans ScsError.panic f
    fun errorDml emsg sql = (Db.panicDml (fn _ => (Ns.log (Ns.Notice, "hej");
						    ScsPage.returnPg "Databasefejl" emsg)) sql;())

    fun panicOneRow (f:(string->string)->'a) (sql:quot) : 'a  = 
      case Db.list f sql of
	[] => ScsError.panic `ScsDb.panicOneRow: No rows`
      | [r] => r
      | _ => ScsError.panic `ScsDb.panicOneRow: More than one row`

    fun panicZeroOrOneRow (f:(string->string)->'a) (sql:quot) : 'a option = 
      case Db.list f sql of
	[] => NONE
      | [r] => SOME r
      | _ => ScsError.panic `ScsDb.panicOneRow: More than one row`

    fun toggleP table column_id column id =
      panicDml `update ^table set ^column=(case when ^column = 't' then 'f' else 't' end)
                 where ^table.^column_id=^(Db.qqq id)`

    fun oneRowErrPg' (f,sql,emsg) =
      Db.oneRow' f sql handle _ => (ScsPage.returnPg "" emsg;Ns.exit())

    fun oneFieldErrPg (sql,emsg) =
      Db.oneField sql handle _ => (ScsPage.returnPg "" emsg;Ns.exit())

    fun userLang user_id = ScsLang.toString ScsLogin.user_lang

    val ppDate = ScsDate.ppDb o Db.toDate

  end








