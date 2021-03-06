require "pencil/models/base"
require "pencil/models/graph"
require "pencil/models/host"
require "set"

module Pencil
  module Models
    class Dashboard < Base
      attr_accessor :graphs
      attr_accessor :graph_opts

      def initialize(name, params={})
        super

        @graphs = []
        @graph_opts = {}
        params["graphs"].each do |n|
          if n.respond_to?(:keys)
            key = n.keys.first # should only be one key
            val = n.values.first
            g = Graph.find(key)
            @graph_opts[g] = val||{}
          else
            raise "Bad format for graph (must be a hash-y; #{n.class}:#{n.inspect} is not)"
          end

          @graphs << g if g
        end

        @valid_hosts_table = {} # cache calls to get_valid_hosts
      end

      def clusters
        clusters = Set.new
        @graphs.each { |g| clusters += get_valid_hosts(g)[1] }
        clusters.sort
      end

      def get_all_hosts(cluster=nil)
        hosts = Set.new
        clusters = Set.new
        @graphs.each do |g|
          h, c = get_valid_hosts(g, cluster)
          hosts += h
          clusters += c
        end
        return hosts, clusters
      end

      def get_valid_hosts(graph, cluster=nil)
        if @valid_hosts_table[[graph, cluster]]
          return @valid_hosts_table[[graph, cluster]]
        end

        clusters = Set.new
        if cluster
          hosts = Host.find_by_cluster(cluster)
        else
          hosts = Host.all
        end

        # filter as:
        #   - the dashboard graph hosts definition
        #   - the dashboard hosts definition
        #   - the graph hosts definition
        # this is new behavior: before the filters were additive
        filter = graph_opts[graph]["hosts"] || @params["hosts"] || graph["hosts"]
        if filter
          hosts = hosts.select { |h| h.multi_match(filter) }
        end

        hosts.each { |h| clusters << h.cluster }

        @valid_hosts_table[[graph, cluster]] = [hosts, clusters]
        return hosts, clusters
      end

      def render_cluster_graph(graph, clusters, opts={})
        # FIXME: edge case where the dash filter does not filter to a subset of
        # the hosts filter

        hosts = get_host_wildcards(graph)

        # graphite doesn't support strict matching (as /\d+/), so we need to
        # enumerate the hosts if a "#" wildcard is found
        if ! (filter = hosts.select { |h| h =~ /#/ }).empty?
          hosts_new = hosts - filter
          hosts2 = Host.all.select { |h| h.multi_match(filter) }
          hosts = (hosts2.map {|h| h.name } + hosts_new).sort.uniq.join(',')
        end

        opts[:sum] = :cluster unless opts[:zoom]
        graph_url = graph.render_url(hosts.to_a, clusters, opts)
        return graph_url
      end

      def get_host_wildcards(graph)
        return graph_opts[graph]["hosts"] || @params["hosts"] || graph["hosts"]
      end

      def render_global_graph(graph, opts={})
        hosts = get_host_wildcards(graph)
        _, clusters = get_valid_hosts(graph)

        type = opts[:zoom] ? :cluster : :global
        options = opts.merge({:sum => type})
        graph_url = graph.render_url(hosts, clusters, options)
        return graph_url
      end

      def self.find_by_graph(graph)
        ret = []
        Dashboard.each do |name, dash|

          if dash["graphs"].map { |x| x.keys.first }.member?(graph.name)
            ret << dash
          end
        end

        return ret
      end
    end # Pencil::Models::Dashboard
  end
end # Pencil::Models
