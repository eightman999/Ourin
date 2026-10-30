@handle("OnOurinCounter")
def ourin_counter(value, **kwargs):
    phiori.var["OurinCount"] = phiori.var.get("OurinCount", 0) + 1
    write("{} {}", value, phiori.var["OurinCount"])
