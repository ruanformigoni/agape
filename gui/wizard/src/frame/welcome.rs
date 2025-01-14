use std::env;
use std::path::PathBuf;

// Gui
use fltk::prelude::*;
use fltk::{
  app::Sender,
  input::FileInput,
  frame::Frame,
  dialog::dir_chooser,
  enums::Align,
};

use shared::fltk::SenderExt;
use anyhow::anyhow as ah;

use crate::db;
use crate::gameimage;
use crate::dimm;
use crate::common;
use crate::log_status;
use shared::svg;
use shared::std::PathBufExt;
use shared::{column,row,add,fixed};

// check_version() {{{
fn check_version() -> anyhow::Result<()>
{
  let db_fetch = match db::fetch::read()
  {
    Ok(db) => db,
    Err(e) => return Err(ah!("error: could not read fetch.json, backend failed? No internet? '{}", e)),
  }; // match

  let version = db_fetch.version;
  if ! version.starts_with("1.6")
  {
    return Err(ah!("error: you should update to version {}", version));
  } // if

  Ok(())
} // check_version() }}}

// pub fn welcome() {{{
pub fn welcome(tx: Sender<common::Msg>, title: &str)
{
  let ui = crate::GUI.lock().unwrap().ui.clone()(title);

  column!(col,
    add!(col, spacer, Frame::default());
    row!(row,
      add!(row, spacer, Frame::default());
      fixed!(row, frame_image, Frame::default(), dimm::height_button_wide()*4);
      add!(row, spacer, Frame::default());
    );
    col.fixed(&row, dimm::height_button_wide()*4);
    add!(col, spacer, Frame::default());
    fixed!(col, _label, Frame::default()
        .with_align(Align::Left | Align::Inside)
        .with_label("Select The Directory for GameImage's Temporary Files")
      , dimm::height_text());
    fixed!(col, input_dir, FileInput::default(), dimm::height_button_wide() + dimm::border_half());
  );

  // Image
  let mut frame_image = frame_image.clone();
  frame_image.set_align(Align::Inside | Align::Bottom);
  frame_image.set_image_scaled(fltk::image::SvgImage::from_data(svg::ICON_GAMEIMAGE).ok());

  // Input
  let mut input_dir = input_dir.clone();
  input_dir.set_pos(dimm::border(), input_dir.y());
  input_dir.set_readonly(true);
  input_dir.set_value(&env::var("GIMG_DIR").unwrap_or_default());
  input_dir.set_callback(move |e|
  {
    let mut path_selected = match dir_chooser("Select the build directory", "", false)
    {
      Some(value) => PathBuf::from(value),
      None => { log_status!("No file selected"); return; },
    };
    // Set build dir as chosen dir + /build
    path_selected = path_selected.join("build");
    // Update chosen dir in selection bar
    e.set_value(&path_selected.string());
    // Set env var to build dir
    env::set_var("GIMG_DIR", &path_selected.string());
  });

  // Set callback for next
  let clone_tx = tx.clone();
  ui.btn_next.clone().set_callback(move |_|
  {
    let path_dir_build = match env::var("GIMG_DIR")
    {
      Ok(value) => PathBuf::from(value),
      Err(e) => { log_status!("Invalid temporary files directory: {}", e); return; }
    }; // if
    // Create build directory
    match std::fs::create_dir_all(&path_dir_build)
    {
      Ok(()) => (),
      Err(e) => log_status!("Could not create build directory: {}", e),
    }
    // Init project build directory
    match gameimage::init::build(path_dir_build)
    {
      Ok(()) => (),
      Err(e) => log_status!("Error to initialize build directory: {}", e)
    }; // match
    // Fetch fetch list
    match gameimage::fetch::sources()
    {
      Ok(code) => log_status!("Fetch exited with code {}", code),
      Err(e) => log_status!("Error to initialize build directory: {}", e)
    }; // match
    // Check if version matches
    if let Err(e) = check_version()
    {
      log_status!("{}", e);
      fltk::dialog::message_default(&format!("{}", e));
      clone_tx.send_awake(common::Msg::WindActivate);
      return;
    } // if
    // Draw creator frame
    clone_tx.send_awake(common::Msg::DrawCreator);
  });
} // fn: welcome }}}

// vim: set expandtab fdm=marker ts=2 sw=2 tw=100 et :
