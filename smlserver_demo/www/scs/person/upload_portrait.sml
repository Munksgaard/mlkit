val user_id = ScsLogin.auth()

val (mode,errs) = (* Default mode is upload *)
  ScsFormVar.wrapMaybe_nh "upload" 
  (ScsFormVar.getEnumErr ["upload","rotate","delete"]) ("mode","mode",ScsFormVar.emptyErr)
val (person_id,errs) = ScsPerson.getPersonIdErr("person_id",errs)
val _ = ScsFormVar.anyErrors errs

val (per_opt,errs) = ScsPerson.getPersonErr (person_id,ScsFormVar.emptyErr)
val _ = ScsFormVar.anyErrors errs
val per = ScsError.valOf per_opt (* We now know for sure, that there is a person *)
val priv = ScsPerson.uploadPortraitPriv (user_id,per)

fun delPortrait db (p:ScsPerson.portrait_record option) =
  case p of
    NONE => ()
  | SOME p => ScsPerson.delPortrait db p
      
fun delPortraitFS db priv (p:ScsPerson.portrait_record option) = 
  (* Suppress all errors, e.g., priviledges, file not found *)
  case p of
    NONE => ()
  | SOME p => 
      (ScsFileStorage.delFileErr db ScsPerson.upload_root_label (priv,#file_id p,ScsFormVar.emptyErr);())

fun getFormat filename =
  let
    val (format_opt,errs) = ScsPicture.identifyPictureErr (filename,ScsFormVar.emptyErr)
    val _ = ScsFormVar.anyErrors errs
  in
    ScsError.valOf format_opt
  end

fun delTmpFiles files = List.app (fn f => FileSys.remove f handle _ => ()) files

val files_to_delete_on_error = ref []
fun addFileToDeleteOnError f = files_to_delete_on_error := f :: (!files_to_delete_on_error)

val _ =
  (* Access control *)
  if ScsList.contains priv [ScsFileStorage.no_priv,ScsFileStorage.read] orelse
    (mode = "delete" andalso priv = ScsFileStorage.read_add) then
    ScsFormVar.anyErrors
    (ScsFormVar.addErr(ScsDict.s' [(ScsLang.da,`Du har ikke rettigheder til at rette billede for
				    ^(#name per).`),
				   (ScsLang.en,`You are not allowed to update picture on ^(#name per).`)],
		       ScsFormVar.emptyErr)) (* Return if no priviledges to upload pictures. *)
  else
    case mode of
      "delete" => 
	let
	  (* Look for pictures to delete. *)
	  val portraits = ScsPerson.getPortraits person_id
	  val pic_thumb_opt = ScsPerson.getPicture ScsPerson.thumb_fixed_height false portraits
	  val pic_orig_opt = ScsPerson.getPicture ScsPerson.original false portraits

	  fun delete db =
	    let
	      (* Delete pictures from scs_portraits *)
	      val _ = delPortrait db pic_thumb_opt
	      val _ = delPortrait db pic_orig_opt
	      (* Delete pictures from FS - suppress errors *)
	      val _ = delPortraitFS db priv pic_thumb_opt
	      val _ = delPortraitFS db priv pic_orig_opt
	    in
	      ()
	    end
	in
	  ScsError.wrapPanic Db.Handle.dmlTrans delete
	end
    | "rotate" => 
	let
	  val (direction_opt,errs) = ScsPicture.getDirectionErr("direction",ScsFormVar.emptyErr)
	  val _ = ScsFormVar.anyErrors errs
	  val direction = ScsError.valOf direction_opt (* We now know that a direction is given *)

	  (* Look for pictures to rotate. *)
	  val portraits = ScsPerson.getPortraits person_id
	  val pic_thumb_opt = ScsPerson.getPicture ScsPerson.thumb_fixed_height false portraits
	  val pic_orig_opt = ScsPerson.getPicture ScsPerson.original false portraits

	  fun updPortrait db file_id pic_format =
	    ScsError.wrapPanic (Db.Handle.dmlDb db)
	      `update scs_portraits
                  set ^(Db.setList [("width",Int.toString (#width pic_format)),
                                    ("height",Int.toString (#height pic_format)),
                                    ("bytes",Int.toString (#size pic_format))])
                where file_id = '^(Int.toString file_id)'`
	  fun rotate db =
	    case (pic_thumb_opt,pic_orig_opt) of
	      (SOME pic_thumb,SOME pic_orig) => 
		let
		  val orig_file_opt = 
		    ScsFileStorage.getFileByFileId ScsPerson.upload_root_label (#file_id pic_orig)
		  val thumb_file_opt = 
		    ScsFileStorage.getFileByFileId ScsPerson.upload_root_label (#file_id pic_thumb)
		in
		  case (orig_file_opt,thumb_file_opt) of
		    (SOME orig_file,SOME thumb_file) =>
		      let
			(* Rotate original picture *)
			val orig_phys_file = #path_on_disk orig_file ^ "/" ^ (#filename_on_disk orig_file)
			val orig_tmp = 
			  ScsConfig.scs_tmp() ^ "/" ^ (ScsFile.uniqueFile (ScsConfig.scs_tmp())) ^ 
			  "." ^ (#file_ext (#mime_type orig_file))
			val _ = addFileToDeleteOnError orig_tmp
			val errs = ScsPicture.rotatePicture (orig_phys_file,orig_tmp,direction,
							     ScsFormVar.emptyErr)
			val _ = ScsFormVar.anyErrors errs
			val orig_tmp_format = getFormat orig_tmp
		
			(* mk thumbnail in tmp directory *)
			val (h,w) = ScsPicture.fixedHeight orig_tmp_format ScsPerson.thumb_height
			val thumb_tmp = ScsConfig.scs_tmp() ^ "/" ^ (ScsFile.uniqueFile (ScsConfig.scs_tmp())) ^
			  "." ^ (#file_ext (#mime_type orig_file))
			val _ = addFileToDeleteOnError thumb_tmp
			val errs = ScsPicture.convertPicture (h,w,"-sharpen 3 -quality 90",
							      orig_tmp,thumb_tmp,ScsFormVar.emptyErr)
			val _ = ScsFormVar.anyErrors errs
			val thumb_tmp_format = getFormat thumb_tmp
			  
		      (* Replace files in FS, that is, replace files on disk AND update both
		         FS and scs_portraits *)
			val _ = updPortrait db (#file_id orig_file) orig_tmp_format
			val _ = updPortrait db (#file_id thumb_file) thumb_tmp_format
			val errs = (* We rotate, so no limit on size - we have already accepted the picture once. *)
			  ScsFileStorage.replaceFile (db,user_id,orig_file,ScsFileStorage.admin,
						      orig_tmp,ScsFormVar.emptyErr)
			val _ = ScsFormVar.anyErrors errs
			val errs = (* We rotate, so no limit on size - we have already accepted the picture once. *)
			  ScsFileStorage.replaceFile (db,user_id,thumb_file,ScsFileStorage.admin,
						      thumb_tmp,ScsFormVar.emptyErr)
			val _ = ScsFormVar.anyErrors errs
		      in
			[thumb_tmp,orig_tmp]
		      end
		  | _ => [] (* If one picture does not exists, then do nothing. *)
		end
	    | _ => [] (* If one picture does not exists, then do nothing. *)
	in
	  delTmpFiles (Db.Handle.dmlTrans rotate)
	  handle X => (delTmpFiles (!files_to_delete_on_error); raise X)
	end
    | "upload" => 
	let
	  val (upload_filename,errs) = ScsFileStorage.getFilenameErr("upload_filename",ScsFormVar.emptyErr)
	  val _ = ScsFormVar.anyErrors errs
	  (* Only keep filename (i.e., throw away directory) *)
	  val filename = (ScsPathMac.file o ScsPathWin.file o ScsPathUnix.file) upload_filename

	  (* Error handling is a bit tricky: 
               We have
                 * tmp files in tmp directory
                 * old rows in scs_portraits
                 * old files in FS tables
                 * old files in FS file system

                 * new rows in scs_portraits
                 * new files in FS tables
                 * new files in FS file system

           How do we obtain a wel-defined database and filesystem if
  	   errors happen during the transaction? If an error happens
	   during storeFile the database is automatically rolled back to
	   having the old pictures uploaded. How do we ensure that the
	   file system contains the old files only?

             1 we wait deleting old files from FS till the new files
               has been installed in both database and file system.
               We allow up to six files in each FS directory which
               should be adequate even though we have both new and old
               pictures stored at the same time for at short time.
               Notice, that the filename stored in DB is made
               unique in case the user uploades the same file several
               times (i.e., FS does not allow two files with the same
               name in the same directory of course).

             2 we always try deleting tmp files from the temporary
               directory after the transaction.

             3 in case the transaction is rolled back we delete
               the physical files that have been created in FS so far *)
	  fun storeFile db : string list = (* returns temporary files to delete *)
	    let
	      val folder_id = ScsPerson.getOrCreateUploadFolderId(db,per)
		
	      (* Save uploaded picture in temporary directory. *)
	      val unique_id = ScsDb.newObjIdDb db
	      val filename = (Int.toString unique_id) ^ "-" ^ filename
	      val orig_filename_tmp = ScsConfig.scs_tmp() ^ "/" ^ filename
	      val _ = addFileToDeleteOnError orig_filename_tmp
	      val errs = ScsFileStorage.storeMultiformData("upload_filename",orig_filename_tmp,
							   ScsFormVar.emptyErr)
	      val _ = ScsFormVar.anyErrors errs
	      (* check original format. *)
	      val orig_format = getFormat orig_filename_tmp
	    
	      (* mk original picture in max size (800x600) in tmp-directory *)
	      val (orig_tmp,orig_tmp_format) =
		if #height orig_format > ScsPerson.max_height then
		  let
		    val (h,w) = ScsPicture.fixedHeight orig_format ScsPerson.max_height
		    val orig_tmp = ScsConfig.scs_tmp() ^ "/" ^ "orig_tmp-" ^ filename
		    val _ = addFileToDeleteOnError orig_tmp
		    val errs = ScsPicture.convertPicture (h,w,"-sharpen 3 -quality 100",
							  orig_filename_tmp,orig_tmp,ScsFormVar.emptyErr)
		    val _ = ScsFormVar.anyErrors errs
		  in
		    (orig_tmp,getFormat orig_tmp)
		  end
		else
		  (orig_filename_tmp,orig_format)
		  
	      (* mk thumbnail in tmp directory *)
	      val (h,w) = ScsPicture.fixedHeight orig_format ScsPerson.thumb_height
	      val thumb_tmp = ScsConfig.scs_tmp() ^ "/" ^ "thumb-" ^ filename
	      val _ = addFileToDeleteOnError thumb_tmp
	      val errs = ScsPicture.convertPicture (h,w,"-sharpen 3 -quality 90",
						    orig_filename_tmp,thumb_tmp,ScsFormVar.emptyErr)
	      val _ = ScsFormVar.anyErrors errs
	      (* check thumbnail format. *)
	      val thumb_format = getFormat thumb_tmp
   
	      (* Now we have the two pictures, so we move on inserting them into FS *)
	      (* Delete old pictures from scs_portraits *)
	      val old_portraits = ScsPerson.getPortraits person_id
	      val _ = delPortrait db (ScsPerson.getPicture ScsPerson.thumb_fixed_height false old_portraits)
	      val _ = delPortrait db (ScsPerson.getPicture ScsPerson.original false old_portraits)

	      (* Upload original picture *)
	      val (file_id,phys_file_fs_orig,errs) = 
		ScsFileStorage.storeFile (db,user_id,folder_id,priv,orig_tmp,
					  filename,
					  "Non official portrait - original size")
	      val _ = addFileToDeleteOnError phys_file_fs_orig
	      val _ = ScsFormVar.anyErrors errs
	      val orig_pic : ScsPerson.portrait_record =
		{ file_id = file_id,
		 party_id = person_id,
		 portrait_type_vid = 0, (* Arbitrary value *)
		 portrait_type_val = ScsPerson.original,
		 filename          = "", (* Arbitrary value *)
		 url               = "", (* Arbitrary value *)
		 width             = #width orig_tmp_format,
		 height            = #height orig_tmp_format,
		 bytes             = #size orig_tmp_format,
		 official_p        = false,
		 person_name       = "",
		 may_show_portrait_p = false (* Arbitraty value *)}
	      val _ = ScsPerson.insPortrait db orig_pic

	      (* Upload thumbnail *)
	      val (file_id,phys_file_fs_thumb,errs) = 
		ScsFileStorage.storeFile (db,user_id,folder_id,priv,thumb_tmp,
					  "fixed_height_thumb_"^filename,
					  "Non official portrait - thumbnail")
	      val _ = addFileToDeleteOnError phys_file_fs_thumb
	      val _ = ScsFormVar.anyErrors errs
	      val thumb_pic : ScsPerson.portrait_record =
		{ file_id = file_id,
		 party_id = person_id,
		 portrait_type_vid = 0, (* Arbitrary value *)
		 portrait_type_val = ScsPerson.thumb_fixed_height,
		 filename          = "", (* Arbitrary value *)
		 url               = "", (* Arbitrary value *)
		 width             = #width thumb_format,
		 height            = #height thumb_format,
		 bytes             = #size thumb_format,
		 official_p        = false,
		 person_name       = "",
		 may_show_portrait_p = false (* Arbitraty value *)}
	      val _ = ScsPerson.insPortrait db thumb_pic

	      (* No error has happened, so we continue cleaning up *)
	      (* Delete old pictures from FS if they exists - both DB and file system - suppress errors *)
	      val _ = delPortraitFS db priv (ScsPerson.getPicture ScsPerson.thumb_fixed_height false old_portraits)
	      val _ = delPortraitFS db priv (ScsPerson.getPicture ScsPerson.original false old_portraits)
	    in
	      [orig_filename_tmp,orig_tmp,thumb_tmp] (* Tmp-files to delete when no errors happen. *)
	    end
	in
	  delTmpFiles (Db.Handle.dmlTrans storeFile)
	  handle X => (delTmpFiles (!files_to_delete_on_error); raise X)
	end
    | _ => () (* Unknown mode *)
	
val _ = ScsConn.returnRedirect "/index.sml" [("mode",UcsSs.Widget.modeToString UcsSs.Widget.MY_PROFILE_VIEW)]


