use zed_extension_api as zed;

const SILEX_COMMAND: &str = match option_env!("SILEX_LSP_COMMAND") {
    Some(command) => command,
    None => "silex",
};

struct SilexExtension;

impl zed::Extension for SilexExtension {
    fn new() -> Self {
        Self
    }

    fn language_server_command(
        &mut self,
        _language_server_id: &zed::LanguageServerId,
        _worktree: &zed::Worktree,
    ) -> zed::Result<zed::Command> {
        Ok(zed::Command {
            command: SILEX_COMMAND.to_string(),
            args: vec!["lsp".to_string()],
            env: Vec::new(),
        })
    }
}

zed::register_extension!(SilexExtension);
