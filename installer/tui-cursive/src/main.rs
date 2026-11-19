//! VLANit installer TUI fallback (Cursive). Writes install-config.json and exits.
use cursive::traits::*;
use cursive::views::{
    Dialog, EditView, LinearLayout, ListView, SelectView, TextView,
};
use cursive::Cursive;
use serde_json::{json, Value};
use std::path::PathBuf;
use std::process::Command;
use std::sync::{Arc, Mutex};

#[derive(Default, Clone)]
struct Draft {
    disk: String,
    mirror_disk: String,
    iface: String,
    net_mode: String,
    net_addr: String,
    net_gw: String,
    net_dns: String,
    hostname: String,
    admin_user: String,
    admin_pass: String,
    ssh: String,
    timezone: String,
    wg: String,
    wg_addr: String,
    wg_port: String,
    pbx_name: String,
    pbx_pass: String,
}

fn installer_dir() -> PathBuf {
    std::env::var("INSTALLER_DIR")
        .map(PathBuf::from)
        .unwrap_or_else(|_| PathBuf::from("/opt/vlanit/installer"))
}

fn probe(kind: &str) -> Value {
    let probe = installer_dir().join("bin/vlanit-probe");
    let out = Command::new(&probe)
        .arg(kind)
        .output()
        .unwrap_or_else(|e| panic!("vlanit-probe {kind}: {e}"));
    if !out.status.success() {
        panic!(
            "vlanit-probe {kind} failed: {}",
            String::from_utf8_lossy(&out.stderr)
        );
    }
    serde_json::from_slice(&out.stdout).expect("probe json")
}

fn config_path() -> PathBuf {
    PathBuf::from("/run/vlanit/install-config.json")
}

fn write_config(d: &Draft) {
    let cfg = json!({
        "disk": d.disk,
        "mirror_disk": d.mirror_disk,
        "network": {
            "interface": d.iface,
            "mode": if d.net_mode.is_empty() { "dhcp" } else { &d.net_mode },
            "address": d.net_addr,
            "gateway": d.net_gw,
            "dns": if d.net_dns.is_empty() { "9.9.9.9" } else { &d.net_dns },
        },
        "hostname": if d.hostname.is_empty() { "vlanit-pbx" } else { &d.hostname },
        "admin": {
            "user": if d.admin_user.is_empty() { "vlanit" } else { &d.admin_user },
            "password": d.admin_pass,
        },
        "ssh_enabled": if d.ssh.is_empty() { "yes" } else { &d.ssh },
        "timezone": if d.timezone.is_empty() { "Europe/Moscow" } else { &d.timezone },
        "wireguard": {
            "enabled": if d.wg.is_empty() { "no" } else { &d.wg },
            "address": if d.wg_addr.is_empty() { "10.66.66.1/24" } else { &d.wg_addr },
            "listen_port": if d.wg_port.is_empty() { "51820" } else { &d.wg_port },
        },
        "mikopbx": {
            "name": if d.pbx_name.is_empty() { "VLANit-PBX" } else { &d.pbx_name },
            "web_admin_login": "admin",
            "web_admin_password": d.pbx_pass,
        },
        "confirm": "yes",
        "kernel_args": "",
    });
    std::fs::create_dir_all("/run/vlanit").ok();
    std::fs::write(config_path(), format!("{cfg}\n")).expect("write config");
}

fn show_error(siv: &mut Cursive, msg: &str) {
    siv.add_layer(
        Dialog::text(msg.to_string())
            .title("Ошибка")
            .button("OK", |s| {
                s.pop_layer();
            }),
    );
}

fn screen_hardware(siv: &mut Cursive, draft: Arc<Mutex<Draft>>) {
    let hw = probe("hardware");
    let text = format!(
        "Процессор: {} ({} ядер)\nОЗУ: {} МБ\nИнтерфейсы: {}\nРежим загрузки: {}\n{}",
        hw["cpu"].as_str().unwrap_or(""),
        hw["cores"],
        hw["ram_mb"],
        hw["interfaces"]
            .as_array()
            .map(|a| a
                .iter()
                .filter_map(|v| v.as_str())
                .collect::<Vec<_>>()
                .join(" "))
            .unwrap_or_default(),
        hw["boot_mode"].as_str().unwrap_or(""),
        hw["warnings"].as_str().unwrap_or(""),
    );
    let d = draft.clone();
    siv.add_layer(
        Dialog::around(TextView::new(text))
            .title("Экран 1. Оборудование")
            .button("Далее", move |s| {
                let boot = probe("hardware")["boot_mode"]
                    .as_str()
                    .unwrap_or("")
                    .to_string();
                if boot != "UEFI" {
                    show_error(s, "Требуется UEFI.");
                    return;
                }
                s.pop_layer();
                screen_disk(s, d.clone());
            })
            .button("Выход", |s| s.quit()),
    );
}

fn screen_disk(siv: &mut Cursive, draft: Arc<Mutex<Draft>>) {
    let data = probe("disks");
    let disks = data["disks"].as_array().cloned().unwrap_or_default();
    let mut sel = SelectView::<String>::new().autojump();
    for d in &disks {
        let dev = d["dev"].as_str().unwrap_or("").to_string();
        let label = format!(
            "{}  {} GiB  {}  [{}]",
            dev,
            d["size_gib"],
            d["model"].as_str().unwrap_or(""),
            d["tran"].as_str().unwrap_or("")
        );
        sel.add_item(label, dev);
    }
    let draft2 = draft.clone();
    let draft_back = draft.clone();
    siv.add_layer(
        Dialog::around(sel.with_name("disk").fixed_height(10))
            .title("Экран 2. Диск")
            .button("Далее", move |s| {
                let disk = s
                    .call_on_name("disk", |v: &mut SelectView<String>| v.selection())
                    .flatten()
                    .map(|x| (*x).clone())
                    .unwrap_or_default();
                if disk.is_empty() {
                    show_error(s, "Выберите диск.");
                    return;
                }
                draft2.lock().unwrap().disk = disk.clone();
                s.pop_layer();
                screen_mirror(s, draft2.clone(), disk);
            })
            .button("Назад", move |s| {
                s.pop_layer();
                screen_hardware(s, draft_back.clone());
            }),
    );
}

fn screen_mirror(siv: &mut Cursive, draft: Arc<Mutex<Draft>>, primary: String) {
    let data = probe("disks");
    let disks = data["disks"].as_array().cloned().unwrap_or_default();
    let others: Vec<_> = disks
        .iter()
        .filter(|d| d["dev"].as_str().unwrap_or("") != primary)
        .cloned()
        .collect();
    if others.is_empty() {
        draft.lock().unwrap().mirror_disk.clear();
        screen_network(siv, draft);
        return;
    }
    let mut mode = SelectView::<String>::new();
    mode.add_item("Один диск", "single".into());
    mode.add_item("Зеркало RAID1", "raid1".into());
    let draft2 = draft.clone();
    let draft_back = draft.clone();
    let primary2 = primary.clone();
    siv.add_layer(
        Dialog::around(
            LinearLayout::vertical()
                .child(TextView::new(format!("Основной: {primary}")))
                .child(mode.with_name("mmode")),
        )
        .title("Режим дисков")
        .button("Далее", move |s| {
            let m = s
                .call_on_name("mmode", |v: &mut SelectView<String>| v.selection())
                .flatten()
                .map(|x| (*x).clone())
                .unwrap_or_else(|| "single".into());
            s.pop_layer();
            if m == "raid1" {
                screen_mirror_pick(s, draft2.clone(), primary2.clone());
            } else {
                draft2.lock().unwrap().mirror_disk.clear();
                screen_network(s, draft2.clone());
            }
        })
        .button("Назад", move |s| {
            s.pop_layer();
            screen_disk(s, draft_back.clone());
        }),
    );
}

fn screen_mirror_pick(siv: &mut Cursive, draft: Arc<Mutex<Draft>>, primary: String) {
    let data = probe("disks");
    let disks = data["disks"].as_array().cloned().unwrap_or_default();
    let mut sel = SelectView::<String>::new();
    for d in disks {
        let dev = d["dev"].as_str().unwrap_or("").to_string();
        if dev == primary {
            continue;
        }
        sel.add_item(
            format!("{} ({} GiB)", dev, d["size_gib"]),
            dev,
        );
    }
    let draft2 = draft.clone();
    siv.add_layer(
        Dialog::around(sel.with_name("mdisk"))
            .title("Второй диск зеркала")
            .button("Далее", move |s| {
                let disk = s
                    .call_on_name("mdisk", |v: &mut SelectView<String>| v.selection())
                    .flatten()
                    .map(|x| (*x).clone())
                    .unwrap_or_default();
                if disk.is_empty() {
                    show_error(s, "Выберите второй диск.");
                    return;
                }
                draft2.lock().unwrap().mirror_disk = disk;
                s.pop_layer();
                screen_network(s, draft2.clone());
            }),
    );
}

fn screen_network(siv: &mut Cursive, draft: Arc<Mutex<Draft>>) {
    let data = probe("ifaces");
    let ifaces = data["interfaces"].as_array().cloned().unwrap_or_default();
    let mut isel = SelectView::<String>::new();
    for i in ifaces {
        let name = i["name"].as_str().unwrap_or("").to_string();
        let mac = i["mac"].as_str().unwrap_or("");
        isel.add_item(format!("{name} ({mac})"), name);
    }
    let mut mode = SelectView::<String>::new();
    mode.add_item("DHCP", "dhcp".into());
    mode.add_item("Статический IPv4", "static".into());
    let layout = LinearLayout::vertical()
        .child(TextView::new("Интерфейс"))
        .child(isel.with_name("iface").fixed_height(5))
        .child(TextView::new("Режим"))
        .child(mode.with_name("nmode"))
        .child(TextView::new("Адрес CIDR / шлюз / DNS (для static)"))
        .child(
            ListView::new()
                .child("Адрес:", EditView::new().with_name("addr").fixed_width(28))
                .child("Шлюз:", EditView::new().with_name("gw").fixed_width(28))
                .child(
                    "DNS:",
                    EditView::new()
                        .content("9.9.9.9")
                        .with_name("dns")
                        .fixed_width(28),
                ),
        );
    let draft2 = draft.clone();
    let draft_back = draft.clone();
    siv.add_layer(
        Dialog::around(layout)
            .title("Экран 3. Сеть")
            .button("Далее", move |s| {
                let iface = s
                    .call_on_name("iface", |v: &mut SelectView<String>| v.selection())
                    .flatten()
                    .map(|x| (*x).clone())
                    .unwrap_or_default();
                let nmode = s
                    .call_on_name("nmode", |v: &mut SelectView<String>| v.selection())
                    .flatten()
                    .map(|x| (*x).clone())
                    .unwrap_or_else(|| "dhcp".into());
                let addr = s
                    .call_on_name("addr", |v: &mut EditView| v.get_content())
                    .map(|c| (*c).clone())
                    .unwrap_or_default();
                let gw = s
                    .call_on_name("gw", |v: &mut EditView| v.get_content())
                    .map(|c| (*c).clone())
                    .unwrap_or_default();
                let dns = s
                    .call_on_name("dns", |v: &mut EditView| v.get_content())
                    .map(|c| (*c).clone())
                    .unwrap_or_else(|| "9.9.9.9".into());
                if iface.is_empty() {
                    show_error(s, "Выберите интерфейс.");
                    return;
                }
                if nmode == "static" && (addr.is_empty() || gw.is_empty()) {
                    show_error(s, "Для static укажите адрес и шлюз.");
                    return;
                }
                {
                    let mut d = draft2.lock().unwrap();
                    d.iface = iface;
                    d.net_mode = nmode;
                    d.net_addr = addr;
                    d.net_gw = gw;
                    d.net_dns = dns;
                }
                s.pop_layer();
                screen_system(s, draft2.clone());
            })
            .button("Назад", move |s| {
                s.pop_layer();
                screen_disk(s, draft_back.clone());
            }),
    );
}

fn screen_system(siv: &mut Cursive, draft: Arc<Mutex<Draft>>) {
    let layout = ListView::new()
        .child(
            "Hostname:",
            EditView::new()
                .content("vlanit-pbx")
                .with_name("hostname")
                .fixed_width(24),
        )
        .child(
            "Админ:",
            EditView::new()
                .content("vlanit")
                .with_name("user")
                .fixed_width(24),
        )
        .child(
            "Пароль:",
            EditView::new().secret().with_name("pass").fixed_width(24),
        )
        .child(
            "TZ:",
            EditView::new()
                .content("Europe/Moscow")
                .with_name("tz")
                .fixed_width(24),
        )
        .child(
            "АТС имя:",
            EditView::new()
                .content("VLANit-PBX")
                .with_name("pbx")
                .fixed_width(24),
        )
        .child(
            "АТС пароль:",
            EditView::new().secret().with_name("pbxpass").fixed_width(24),
        );
    let mut ssh = SelectView::<String>::new();
    ssh.add_item("SSH вкл", "yes".into());
    ssh.add_item("SSH выкл", "no".into());
    let outer = LinearLayout::vertical()
        .child(layout)
        .child(ssh.with_name("ssh"));
    let draft2 = draft.clone();
    let draft_back = draft.clone();
    siv.add_layer(
        Dialog::around(outer.scrollable())
            .title("Экран 4. Система")
            .button("Далее", move |s| {
                let hostname = get_edit(s, "hostname");
                let user = get_edit(s, "user");
                let pass = get_edit(s, "pass");
                let tz = get_edit(s, "tz");
                let pbx = get_edit(s, "pbx");
                let pbxpass = get_edit(s, "pbxpass");
                let ssh = s
                    .call_on_name("ssh", |v: &mut SelectView<String>| v.selection())
                    .flatten()
                    .map(|x| (*x).clone())
                    .unwrap_or_else(|| "yes".into());
                if pass.len() < 8 {
                    show_error(s, "Пароль короче 8 символов.");
                    return;
                }
                let tz_path = PathBuf::from("/usr/share/zoneinfo").join(&tz);
                if !tz_path.is_file() {
                    show_error(s, &format!("Неизвестный часовой пояс: {tz}"));
                    return;
                }
                {
                    let mut d = draft2.lock().unwrap();
                    d.hostname = hostname;
                    d.admin_user = user;
                    d.admin_pass = pass;
                    d.timezone = tz;
                    d.ssh = ssh;
                    d.pbx_name = pbx;
                    d.pbx_pass = pbxpass;
                }
                s.pop_layer();
                screen_wireguard(s, draft2.clone());
            })
            .button("Назад", move |s| {
                s.pop_layer();
                screen_network(s, draft_back.clone());
            }),
    );
}

fn screen_wireguard(siv: &mut Cursive, draft: Arc<Mutex<Draft>>) {
    let mut wg = SelectView::<String>::new();
    wg.add_item("Не включать", "no".into());
    wg.add_item("Включить после установки", "yes".into());
    let layout = ListView::new()
        .child(
            "Адрес wg0:",
            EditView::new()
                .content("10.66.66.1/24")
                .with_name("wgaddr")
                .fixed_width(24),
        )
        .child(
            "Порт:",
            EditView::new()
                .content("51820")
                .with_name("wgport")
                .fixed_width(24),
        );
    let outer = LinearLayout::vertical()
        .child(TextView::new("WireGuard VPN после установки:"))
        .child(wg.with_name("wg"))
        .child(layout);
    let draft2 = draft.clone();
    let draft_back = draft.clone();
    siv.add_layer(
        Dialog::around(outer)
            .title("Экран 5. WireGuard")
            .button("Далее", move |s| {
                let wgv = s
                    .call_on_name("wg", |v: &mut SelectView<String>| v.selection())
                    .flatten()
                    .map(|x| (*x).clone())
                    .unwrap_or_else(|| "no".into());
                let wgaddr = get_edit(s, "wgaddr");
                let wgport = get_edit(s, "wgport");
                if wgv == "yes" && !wgport.chars().all(|c| c.is_ascii_digit()) {
                    show_error(s, "Порт WireGuard — целое число.");
                    return;
                }
                {
                    let mut d = draft2.lock().unwrap();
                    d.wg = wgv;
                    d.wg_addr = if wgaddr.is_empty() {
                        "10.66.66.1/24".into()
                    } else {
                        wgaddr
                    };
                    d.wg_port = if wgport.is_empty() {
                        "51820".into()
                    } else {
                        wgport
                    };
                }
                s.pop_layer();
                screen_confirm(s, draft2.clone());
            })
            .button("Назад", move |s| {
                s.pop_layer();
                screen_system(s, draft_back.clone());
            }),
    );
}

fn get_edit(s: &mut Cursive, name: &str) -> String {
    s.call_on_name(name, |v: &mut EditView| v.get_content())
        .map(|c| (*c).clone())
        .unwrap_or_default()
}

fn screen_confirm(siv: &mut Cursive, draft: Arc<Mutex<Draft>>) {
    let d = draft.lock().unwrap().clone();
    let mirror = if d.mirror_disk.is_empty() {
        String::new()
    } else {
        format!("Зеркало: {} + {}\n", d.disk, d.mirror_disk)
    };
    let wg_line = if d.wg == "yes" {
        format!("вкл ({}, порт {})", d.wg_addr, d.wg_port)
    } else {
        "выкл".into()
    };
    let text = format!(
        "Диск: {}\n{}Сеть: {} ({})\nHostname: {}\nTZ: {}\nАдмин: {}\nSSH: {}\nАТС: {}\nWireGuard: {}\n\nВСЕ ДАННЫЕ НА ДИСКЕ БУДУТ УДАЛЕНЫ.",
        d.disk, mirror, d.net_mode, d.iface, d.hostname, d.timezone, d.admin_user, d.ssh, d.pbx_name, wg_line
    );
    let draft2 = draft.clone();
    let draft_back = draft.clone();
    siv.add_layer(
        Dialog::around(TextView::new(text))
            .title("Экран 6. Подтверждение")
            .button("Установить", move |s| {
                write_config(&draft2.lock().unwrap());
                s.quit();
            })
            .button("Назад", move |s| {
                s.pop_layer();
                screen_wireguard(s, draft_back.clone());
            }),
    );
}

fn main() {
    let draft = Arc::new(Mutex::new(Draft {
        net_mode: "dhcp".into(),
        net_dns: "9.9.9.9".into(),
        hostname: "vlanit-pbx".into(),
        admin_user: "vlanit".into(),
        ssh: "yes".into(),
        timezone: "Europe/Moscow".into(),
        wg: "no".into(),
        wg_addr: "10.66.66.1/24".into(),
        wg_port: "51820".into(),
        pbx_name: "VLANit-PBX".into(),
        ..Draft::default()
    }));
    let mut siv = cursive::default();
    siv.set_window_title("VLANit PBX OS — установка");
    screen_hardware(&mut siv, draft);
    siv.run();
    if !config_path().is_file() {
        std::process::exit(1);
    }
}
