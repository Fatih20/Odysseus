/**
* This file is part of Odysseus Web Browser (Copyright Adrian Cochrane 2016).
*
* Odysseus is free software: you can redistribute it and/or modify
* it under the terms of the GNU General Public License as published by
* the Free Software Foundation, either version 3 of the License, or
* (at your option) any later version.
*
* Odysseus is distributed in the hope that it will be useful,
* but WITHOUT ANY WARRANTY; without even the implied warranty of
* MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
* GNU General Public License for more details.

* You should have received a copy of the GNU General Public License
* along with Odysseus.  If not, see <http://www.gnu.org/licenses/>.
*/
/** A small little toolbar providing full access to WebKit's search capabilities
    without taking much screen realestate away from webpages or appearing too
    complex. To be added to a Gtk.Overlay.

Sure this doesn't look elementary's typical find bars, which appear above the
    tabbar, but I didn't like my experience with full-width findbars in
    Epiphany or FireFox. */
public class Odysseus.Overlay.FindToolbar : Gtk.Toolbar {
    private WebKit.FindController controller;
    private bool smartcase;
    private WebKit.FindOptions options;

    private Gtk.Entry search;
    private Gtk.ToolButton next;
    private Gtk.ToolButton prev;

    public signal void counted_matches(string search, uint matche_count);
    public signal void escape_pressed();

    public FindToolbar(WebKit.FindController controller) {
        set_style (Gtk.ToolbarStyle.ICONS);
        icon_size = Gtk.IconSize.SMALL_TOOLBAR;
        this.controller = controller;
        this.options = WebKit.FindOptions.NONE;

        search = new Gtk.Entry();
        search.primary_icon_name = "edit-find-symbolic";
        search.placeholder_text = _("Find in page…");
        search.changed.connect(() => {
            find_in_page();
            search.secondary_icon_name = search.text_length > 0 ?
                    "edit-clear-symbolic" : null;
        });
        search.icon_press.connect((which, pos) => {
            if (which == Gtk.EntryIconPosition.SECONDARY) {
                search.text = "";
                search.secondary_icon_name = null;
                controller.search_finish();
            }
        });
        search.key_press_event.connect((evt) => {
            if (search.text == "") return false;
            if (controller.text != search.text) find_in_page();

            string key = Gdk.keyval_name(evt.keyval);
            if (evt.state == Gdk.ModifierType.SHIFT_MASK) {
                key = "<Shift>" + key;
            }

            switch (key) {
            case "<Shift>Return":
            case "Up":
                controller.search_previous();
                return true;
            case "Return":
            case "Down":
                controller.search_next();
                return true;
            case "Escape":
                escape_pressed();
                return true;
            }

            return false;
        });
        add_widget(search);

        prev = new Gtk.ToolButton(null, "");
        prev.icon_name = "go-up-symbolic";
        prev.tooltip_text = _("Find previous match");
        prev.clicked.connect(controller.search_previous);
        add_widget(prev);
        next = new Gtk.ToolButton(null, "");
        next.icon_name = "go-down-symbolic";
        next.tooltip_text = "Find next match";
        next.clicked.connect(controller.search_next);
        add_widget(next);

        // TODO handle case where this nonstandard icon doesn't exist
        var options = new Header.ButtonWithMenu.from_icon_name(
                "open-menu-symbolic", Gtk.IconSize.SMALL_TOOLBAR);
        options.tooltip_text = _("View search options");
        options.menu = build_options_menu();
        options.button_release_event.connect(() => {
            options.popup_menu();
            return true;
        });
        options.relief = Gtk.ReliefStyle.NONE;
        add_widget(options);
        smartcase = true;

        controller.found_text.connect(found_text_cb);
        controller.failed_to_find_text.connect(failed_to_find_text_cb);
        controller.counted_matches.connect(counted_matches_cb);
    }

    ~FindToolbar() {
        controller.found_text.disconnect(found_text_cb);
        controller.failed_to_find_text.disconnect(failed_to_find_text_cb);
        controller.counted_matches.disconnect(counted_matches_cb);
    }

    private void add_widget(Gtk.Widget widget) {
        var toolitem = new Gtk.ToolItem();
        toolitem.add(widget);
        add(toolitem);
    }

    private Gtk.Menu build_options_menu() {
        var options_menu = new Gtk.Menu();
        var match_case = new Gtk.RadioMenuItem.with_label(null,
                                _("Match Uppercase"));
        match_case.activate.connect(() => {
            smartcase = false;
            options &= ~WebKit.FindOptions.CASE_INSENSITIVE;
            find_in_page();
        });
        options_menu.add(match_case);
        var ignore_case = new Gtk.RadioMenuItem.with_label(match_case.get_group(), _("Ignore Uppercase"));
        ignore_case.activate.connect(() => {
            smartcase = false;
            options |= WebKit.FindOptions.CASE_INSENSITIVE;
            find_in_page();
        });
        options_menu.add(ignore_case);
        var auto_case = new Gtk.RadioMenuItem.with_label(ignore_case.get_group(), _("Auto"));
        auto_case.active = true;
        auto_case.activate.connect(() => {
            smartcase = true;
            options &= ~WebKit.FindOptions.CASE_INSENSITIVE;
            find_in_page();
        });
        options_menu.add(auto_case);
        options_menu.add(new Gtk.SeparatorMenuItem());

        var cyclic = new Gtk.CheckMenuItem.with_label(_("Cyclic Search"));
        cyclic.active = true;
        options |= WebKit.FindOptions.WRAP_AROUND;
        cyclic.toggled.connect(() => {
            toggle_option(WebKit.FindOptions.WRAP_AROUND, cyclic.active);
        });
        options_menu.add(cyclic);
        var wordstart = new Gtk.CheckMenuItem.with_label(_("Match Word Start"));
        wordstart.active = false;
        wordstart.toggled.connect(() => {
            toggle_option(WebKit.FindOptions.AT_WORD_STARTS, wordstart.active);
        });
        options_menu.add(wordstart);
        // If the user doesn't know what CamelCase means,
        // they probably don't want this option. (note the hint in it's name)
        var camelCase = new Gtk.CheckMenuItem.with_label(_("Match CamelCase"));
        camelCase.active = false;
        camelCase.toggled.connect(() => {
            toggle_option(WebKit.FindOptions.TREAT_MEDIAL_CAPITAL_AS_WORD_START, camelCase.active);
        });
        options_menu.add(camelCase);

        options_menu.show_all();
        return options_menu;
    }

    public void find_in_page() {
        if (search.text == "") return;

        var flags = options;
        if (smartcase) {
            // AKA match case if it's mixed.
            if (search.text.down() == search.text || search.text.up() == search.text) {
                flags |= WebKit.FindOptions.CASE_INSENSITIVE;
            }
        }

        controller.search(search.text, flags, uint.MAX);
        controller.count_matches(search.text, flags, uint.MAX);
    }

    private void toggle_option(WebKit.FindOptions opt, bool active) {
        if (active) options |= opt;
        else options &= ~opt;

        find_in_page();
    }

    private void found_text_cb(uint match_count) {
        search.get_style_context().remove_class(Gtk.STYLE_CLASS_ERROR);
        prev.sensitive = next.sensitive = true;
    }

    private void failed_to_find_text_cb() {
        if (search.text != "")
            search.get_style_context().add_class(Gtk.STYLE_CLASS_ERROR);
        prev.sensitive = next.sensitive = false;
    }

    /* Without this event handler, pressing next & prev gives counts of 1 */
    private void counted_matches_cb(uint match_count) {
        counted_matches(controller.text, match_count);
    }

    public override void grab_focus() {
        search.grab_focus();
    }
}
