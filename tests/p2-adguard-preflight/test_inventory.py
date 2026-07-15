import importlib.util, json, pathlib, tempfile, unittest

ROOT=pathlib.Path(__file__).resolve().parents[2]
COLLECTOR=ROOT/"modules/hosts/discovery/_stateful-adguard-inventory.py"

def load():
    spec=importlib.util.spec_from_file_location("adguard_inventory",COLLECTOR);module=importlib.util.module_from_spec(spec);spec.loader.exec_module(module);return module

def raw():
    work="/var/lib/docker/volumes/networking_adguard_work/_data"; config="/home/erik/servarr/machines/discovery/config/adguard"
    def container(name,identifier,image_id,image_ref,state,mounts):
        runtime={"Status":state}
        if name=="adguard":runtime["Health"]={"Status":"healthy"}
        labels={"com.docker.compose.project":"networking","com.docker.compose.service":name,"com.docker.compose.project.working_dir":"/home/erik/servarr/machines/discovery","com.docker.compose.project.config_files":"/home/erik/servarr/machines/discovery/networking.yml","com.docker.compose.oneoff":"False","com.docker.compose.version":"2.32.4"}
        return {"Id":identifier,"Image":image_id,"Name":"/"+name,"RestartCount":0,"Config":{"Image":image_ref,"Labels":labels},"Mounts":mounts,"NetworkSettings":{"Networks":{"homelab-net":{"NetworkID":"9"*64,"IPAddress":"172.30.0.9"}}},"State":runtime}
    adguard_ref="adguard/adguardhome:v0.108.0-b.83@sha256:"+"a"*64;exporter_ref="ghcr.io/henrywhitaker3/adguard-exporter:v1.2.1@sha256:"+"b"*64
    return {"containers":[container("adguard","1"*64,"sha256:"+"2"*64,"adguard/adguardhome:v0.108.0-b.83","running",[{"Type":"volume","Name":"networking_adguard_work","Source":work,"Destination":"/opt/adguardhome/work"},{"Type":"bind","Source":config,"Destination":"/opt/adguardhome/conf"}]),container("adguard-exporter","3"*64,"sha256:"+"4"*64,"ghcr.io/henrywhitaker3/adguard-exporter:v1.2.1","running",[])],"images":{"sha256:"+"2"*64:["adguard/adguardhome@sha256:"+"a"*64],"sha256:"+"4"*64:["ghcr.io/henrywhitaker3/adguard-exporter@sha256:"+"b"*64]},"volume":{"Name":"networking_adguard_work","Driver":"local","Mountpoint":work,"Labels":{"com.docker.compose.project":"networking"},"Scope":"local","Options":{}},"volume_references":["1"*64],"volume_metadata":{"device":50,"inode":60,"uid":65534,"gid":65534,"mode":"0700","regular":False,"directory":True,"symlink":False,"size_bytes":1234},"config_metadata":{"device":51,"inode":61,"uid":1000,"gid":100,"mode":"0755","regular":False,"directory":True,"symlink":False},"collision":{"exists":True,"name":"discovery_adguard_work","driver":"local","mountpoint":"/var/lib/docker/volumes/discovery_adguard_work/_data","labels":{},"references":[]},"servarr":{"commit":"c"*40,"render_sha256":"d"*64,"render_semantics":{"images":{"adguard":adguard_ref,"adguard-exporter":exporter_ref},"mounts":{"adguard":[{"source":config,"target":"/opt/adguardhome/conf","type":"bind"},{"source":"adguard_work","target":"/opt/adguardhome/work","type":"volume"}],"adguard-exporter":[]},"volumes":{"adguard_work":{"external":True,"name":"networking_adguard_work"}}}},"baseline":{"api":{"protection_enabled":True,"filtering_enabled":True,"enabled_filter_count":2,"filter_count":2,"user_rule_count":3,"query_log_enabled":True,"query_sample_count":1,"rewrite_count":4,"stats":{"dns_queries":100,"blocked_filtering":20}},"dns":{"blocked":{"answer_count":1,"status":"NOERROR"},"external":{"answer_count":2,"status":"NOERROR"},"lan_a":{"answer_count":1,"status":"NOERROR"},"lan_aaaa":{"answer_count":0,"status":"NOERROR"},"rewrite":{"answer_count":1,"status":"NOERROR"}},"exporter":{"families":{"adguard_avg_processing_time_seconds":True,"adguard_queries":True,"adguard_queries_blocked":True},"reachable":True,"required_family_count":3}}}

class InventoryTest(unittest.TestCase):
    @classmethod
    def setUpClass(cls):cls.m=load()
    def test_normalizes_exact_value_free_inventory(self):
        inventory=self.m.normalize(raw())
        self.assertEqual([x["name"] for x in inventory["containers"]],["adguard","adguard-exporter"])
        self.assertEqual(inventory["volume"]["ownership"],"65534:65534")
        self.assertEqual(inventory["protected_collision"]["name"],"discovery_adguard_work")
        self.assertEqual(set(inventory["baseline"]["exporter"]["families"]),set(self.m.EXPECTED_EXPORTER_FAMILIES))
        rendered=str(inventory).lower()
        for token in ("password","token","environment","query_name","client_ip","rule_text","metric_value"):self.assertNotIn(token,rendered)
    def test_source_has_no_lifecycle_or_backup_commands(self):
        source=COLLECTOR.read_text().lower()
        for token in ("docker stop","docker rm","compose up","volume rm","prune","snapshot","archive","chown","chmod"):self.assertNotIn(token,source)
    def test_sops_decrypted_env_auth_key_and_quotes_are_transient(self):
        dummy="fixture-only-not-a-real-password"
        for rendered in (dummy,f"'{dummy}'",f'"{dummy}"'):
            with self.subTest(rendered=rendered),tempfile.TemporaryDirectory() as directory:
                path=pathlib.Path(directory)/".env";path.write_text(f"OTHER=value\nADGUARD_PASSWORD={rendered}\n")
                auth=self.m.auth_from_env(path)
                self.assertEqual(auth,{"username":"erik","password":dummy})
                self.assertNotIn(dummy,json.dumps(self.m.normalize(raw())))
        with tempfile.TemporaryDirectory() as directory:
            path=pathlib.Path(directory)/".env";path.write_text("ADGUARD_PASSWORD=one\nADGUARD_PASSWORD=two\n")
            with self.assertRaisesRegex(ValueError,"exactly once"):self.m.auth_from_env(path)
    def test_declared_api_bind_and_transient_exporter_ip(self):
        observations=raw()["containers"]
        self.assertEqual(self.m.ADGUARD_API_BASE,"http://192.168.10.210:8090")
        endpoint=self.m.exporter_metrics_endpoint(observations)
        self.assertEqual(endpoint,"http://172.30.0.9:9618/metrics")
        self.assertNotIn("172.30.0.9",json.dumps(self.m.normalize(raw())))
        for networks in ({"homelab-net":{"IPAddress":""}},{"homelab-net":{"IPAddress":"not-an-ip"}},{"homelab-net":{"IPAddress":"172.30.0.9"},"other":{"IPAddress":"172.31.0.2"}}):
            changed=raw()["containers"]
            next(item for item in changed if item["Name"]=="/adguard-exporter")["NetworkSettings"]["Networks"]=networks
            with self.subTest(networks=networks),self.assertRaisesRegex(ValueError,"network metadata invalid"):self.m.exporter_metrics_endpoint(changed)
    def test_exporter_family_diagnostic_is_allowlisted_metadata_only(self):
        exposition='''# HELP adguard_queries Query count 999
# TYPE adguard_queries gauge
adguard_queries{client="private",server="hidden"} 999
# TYPE adguard_queries_blocked gauge
# TYPE adguard_avg_processing_time_seconds gauge
# TYPE adguard_queries counter
# TYPE malformed-name counter
# TYPE adguard_dns_queries counter
'''
        diagnostic=self.m.exporter_family_diagnostic(exposition)
        self.assertEqual(diagnostic,{"families":{"adguard_avg_processing_time_seconds":True,"adguard_queries":True,"adguard_queries_blocked":True},"required_family_count":3})
        output=self.m.format_exporter_family_diagnostic(diagnostic)
        self.assertEqual(output,"adguard_avg_processing_time_seconds=true\nadguard_queries=true\nadguard_queries_blocked=true\nrequired_family_count=3\n")
        for forbidden in ("{","}","client","server","private","hidden","999","HELP","TYPE","adguard_dns_queries","malformed-name"):
            self.assertNotIn(forbidden,output)
        missing=self.m.exporter_family_diagnostic("# TYPE adguard_queries counter\n")
        self.assertEqual(missing["required_family_count"],1);self.assertFalse(missing["families"]["adguard_queries_blocked"])

if __name__=="__main__":unittest.main()
