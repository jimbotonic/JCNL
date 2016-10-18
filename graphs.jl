#
# JCNL: Julia Complex Networks Library
# Copyright (C) 2016  Jimmy Dubuisson <jimmy.dubuisson@gmail.com>
#
# This program is free software: you can redistribute it and/or modify
# it under the terms of the GNU General Public License as published by
# the Free Software Foundation, either version 3 of the License, or
# (at your option) any later version.
#
# This program is distributed in the hope that it will be useful,
# but WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
# GNU General Public License for more details.
#

using Graphs, DataStructures, Logging

###
# Basic stats for directed graphs
###

# get # vertices, # of edges and density
# NB: for computing density, we assume a directed graph
function get_basic_stats(g)
	nvs = length(vertices(g))
	nes = num_edges(g)
	density = nes/(nvs*(nvs-1))
	return nvs,nes,density
end

# display basic stats
function display_basic_stats(g,rg)
	nvs,nes,dens = get_basic_stats(g)
	nvs2,nes2,dens2 = get_basic_stats(rg)

	avg_od,max_od,sinks = get_out_degree_stats(g)
	avg_id,max_id,sources = get_out_degree_stats(rg)

	@info("# vertices: $nvs")
	@info("# edges: $nes")
	@info("density: $dens")
	@info()
	@info("avg out-degree: $avg_od")
	@info("max out-degree: $max_od")
	nsinks = length(sinks)
	@info("# sinks: $nsinks")
	@info()
	@info("avg in-degree: $avg_id")
	@info("max in-degree: $max_id")
	nsources = length(sources)
	@info("# sources: $nsources")
end

# get out degree stats
#
# retuns avg out-degree, max out-degree, array of sinks vertices
function get_out_degree_stats{T<:Unsigned}(g::GenericAdjacencyList{T,Array{T,1},Array{Array{T,1},1}})
	sum = 0
	sinks = T[]
	max_degree = 0
	vs = vertices(g)
	for v in vs
		children = out_neighbors(v,g)
		od = length(children)
		sum += od
		if od == 0
			push!(sinks,v)
		end
		if od > max_degree
			max_degree = od
		end
	end
	return sum/length(vs),max_degree,sinks
end

# get array of sink vertices in the specified graph
function get_sinks{T<:Unsigned}(g::GenericAdjacencyList{T,Array{T,1},Array{Array{T,1},1}})
	sinks = T[]
	vs = vertices(g)
	for v in vs
		children = out_neighbors(v,g)
		od = length(children)
		if od == 0
			push!(sinks,v)
		end
	end
	return sinks
end

# get array of source vertices in the specified graph
function get_sources{T<:Unsigned}(g::GenericAdjacencyList{T,Array{T,1},Array{Array{T,1},1}})
	achildren = T[]
	vs = vertices(g)
	for v in vs
		children = out_neighbors(v,g)
		achildren = union(achildren,children)
	end
	return setdiff(vs,achildren)
end

###
# Subgraphs && SCCs
###

# get the subgraph of g induced by the set of vertices sids
function subgraph{T<:Unsigned}(g::GenericAdjacencyList{T,Array{T,1},Array{Array{T,1},1}},sids::Array{T,1})
	ng = adjlist(T, is_directed=true)
	# nvs should be sorted in acending order
	nvs = sort(sids)

	# add vertices
	for i in 1:length(nvs)
        	add_vertex!(ng,convert(T,i))
	end

	# old id -> new id
	oni = Dict{T,T}()
	noi = Dict{T,T}()

	counter = convert(T,1)
	for v in nvs
		oni[v] = counter
		noi[counter] = v
		counter += convert(T,1)
	end

	# add edges
	for v in nvs
		children = out_neighbors(v,g)
		source = oni[v]
		for c in children
			#if index_sorted(nvs,c) != 0
			if haskey(oni,c)
				target = oni[c]
				add_edge!(ng,source,target)
			end
		end
	end
	return ng,oni,noi
end

# get the subgraph of g induced by the set of vertices sids
# write the subgraph in MGS format v2
function subgraph_streamed{T<:Unsigned}(g::GenericAdjacencyList{T,Array{T,1},Array{Array{T,1},1}}, sids::Array{T,1}, name::String)
	ng = adjlist(T, is_directed=true)
	# nvs should be sorted in acending order
	nvs = sort(sids)

	f1 = open("$name.index", "w")
	f2 = open("$name.data", "w")

	# old id -> new id
	oni = Dict{T,T}()

	counter = convert(T,1)
	for v in nvs
		oni[v] = counter
		counter += convert(T,1)
	end

	pos = convert(T,1)
	for v in nvs
		children = out_neighbors(v,g)
		bytes = reinterpret(Uint8, [pos])
                write(f1, reverse(bytes))
		for c in children
			if haskey(oni,c)
				target = oni[c]
				bytes = reinterpret(Uint8, [target])
                		write(f2, reverse(bytes))
				# pos += convert(Uint32, 1) -> 8 bytes!?
				pos = convert(T,pos+1)
			end
		end
	end

	@debug("# vertices: ", length(nvs))
	@debug("# edges: ", pos)

	close(f1)
	close(f2)

	return oni
end

# get the main SCC
function get_core{T<:Unsigned}(g::GenericAdjacencyList{T,Array{T,1},Array{Array{T,1},1}})
	sccs = pearce_iterative(g)
	scc_ids = union(sccs,[])
	id_size = Dict{T,T}()

	for id in scc_ids
		id_size[id] = 0
	end

	for id in sccs
		id_size[id] += 1
	end

	sizes = collect(values(id_size))
	sort!(sizes)
	msize = sizes[end]

	# find the max SCC id
	mid = 0
	for id in keys(id_size)
		id_size[id] == msize && begin mid = id; break end
	end

	sids = T[]
	counter = convert(T,1)
	for id in sccs
		id == mid && push!(sids,counter)
		counter = convert(T,counter+1)
	end

	@debug("# core vids: ", length(sids))

	return subgraph(g,sids)
end
# get the main SCC and write it to the specified file (MGS format)
# write the subgraph in MGS format v2
function get_core_streamed{T<:Unsigned}(g::GenericAdjacencyList{T,Array{T,1},Array{Array{T,1},1}},sccs::Array{T,1},name::String)
	scc_ids = union(sccs,[])
	id_size = Dict{T,T}()

	for id in scc_ids
		id_size[id] = 0
	end

	for id in sccs
		id_size[id] += 1
	end

	sizes = collect(values(id_size))
	sort!(sizes)
	msize = sizes[end]

	# find the max SCC id
	mid = 0
	for id in keys(id_size)
		id_size[id] == msize && begin mid = id; break end
	end

	sids = T[]
	counter = convert(T,1)
	for id in sccs
		id == mid && push!(sids,counter)
		counter = convert(T,counter+1)
	end

	@debug("# core vids: ", length(sids))

	subgraph_streamed(g,sids,name)
end

# get the reverse graph (same graph with all edge directions reversed)
function get_reverse_graph{T<:Unsigned}(g::GenericAdjacencyList{T,Array{T,1},Array{Array{T,1},1}})
	ng = adjlist(T, is_directed=true)
	vs = vertices(g)

	# same set of vertices
	for v in vs
		add_vertex!(ng,v)
	end

	# inverse the edge directions
	for v in vs
		children = out_neighbors(v,g)
		for c in children
			add_edge!(ng,c,v)
		end
	end

	return ng
end

# get in-degree of g vertices
# returns a dictionary (vertex_id -> in-degree)
function get_vertex_in_degrees{T<:Unsigned}(g::GenericAdjacencyList{T,Array{T,1},Array{Array{T,1},1}})
	vin = Dict{T,T}()
	for v in vertices(g)
		ovs = out_neighbors(v,g)
		for o in ovs
			if !haskey(vin,o)
				vin[o] = convert(T,1)
			else
				vin[o] = convert(T,vin[o]+1)
			end
		end
	end
	return vin
end

# get in- and out- degree arrays of specified graph
function get_in_out_degrees{T<:Unsigned}(g::GenericAdjacencyList{T,Array{T,1},Array{Array{T,1},1}})
	vin = get_vertex_in_degrees(g)
	in_degrees = T[]
	out_degrees = T[]
	for v in vertices(g)
		push!(in_degrees,vin[v])
		push!(out_degrees,convert(T,length(out_neighbors(v,g))))
	end
	return in_degrees,out_degrees
end

# get the avg out-degree of the specified set of visited nodes
#
# p_avg: current average
# nb_steps: number of points used to compute p_avg
#
# NB: to get the avg in-degree of visited nodes, one can use the reverse graph of g
function get_avg_out_degree{T<:Unsigned}(g::GenericAdjacencyList{T,Array{T,1},Array{Array{T,1},1}}, visited::Array{T,1}, p_avg::Float64=float64(-1), np_steps::Uint64=uint64(0))
	sum = float64(0)
	for v in visited
		sum += length(out_neighbors(v,g))
	end
	if p_avg != -1
		return (p_avg*np_steps+sum)/(np_steps+length(visited))
	else
		return sum/length(visited)
	end
end

# get a ball centered at the specified vertex
function get_forward_ball{T<:Unsigned}(v::T,g::GenericAdjacencyList{T,Array{T,1},Array{Array{T,1},1}},radius::Int=2,p::Float64=1)
	# vertex ids of the ball
	subids = T[]
	push!(subids,v)
	# set of explored vertices
	explored = T[]
	for t in 1:radius
		so = T[]
		for u in subids
			if !(u in explored)
				append!(so,out_neighbors(u,g))
				push!(explored,u)
			end
		end
		if length(so) > 0
			#  if the probability is 1, add the child
			if p == 1
				append!(subids,unique(so))
			else
				# we are at the first level of the BFS
				if t == 1
					append!(subids,unique(so))
				else
					so = unique(so)
					#added = false
					# select children at random with an exponentially decreasing probability
					for s in so
						if rand() <= p^(t-1)
							push!(subids,s)
							#added = true
						end
					end
					# if no child was added, add at least one at random
					#!added && push!(subids,so[rand(1:length(so))])
				end
			end
		end
	end
	return unique(subids)
end

# get the array of clustering coefficients
#
# ncolinks: array of the number of colinks for each vertex
function get_clustering_coefficients{T<:Unsigned}(g::GenericAdjacencyList{T,Array{T,1},Array{Array{T,1},1}},rg::GenericAdjacencyList{T,Array{T,1},Array{Array{T,1},1}},ntriangles::Array{T,1},density::Float64=-1.)
	vs = vertices(g)
	n = length(vs)
	ccs = zeros(Float64,n)
	for v in vs
		parents = out_neighbors(v,rg)
		children = out_neighbors(v,g)
		p = length(parents)
		c = length(children)
		i = length(intersect(parents,children))
		# maximum number of triangles:
		# = (p_minus_c * c_minus_p) + i * (p_minus_c + c_minus_p + (i - 1))
		# = p*c - i
		npt = p*c-i
		# if there is only 1 colink, no triangle can be formed
		if npt == 0
			ccs[v] = 0
		else
			# correct the result according to the specified density
			if density > 0
				ccs[v] = (ntriangles[v] - density*npt)/(npt*(1-density))
			else
				ccs[v] = ntriangles[v]/npt
			end
		end
	end
	return ccs
end

# get the array of colink coefficients
#
# ncolinks: array of the number of colinks for each vertex
function get_colink_coefficients{T<:Unsigned}(g::GenericAdjacencyList{T,Array{T,1},Array{Array{T,1},1}},rg::GenericAdjacencyList{T,Array{T,1},Array{Array{T,1},1}},ncolinks::Array{T,1},density::Float64=-1.)
	vs = vertices(g)
	n = length(vs)
	ccs = zeros(Float64,n)
	for v in vs
		parents = out_neighbors(v,rg)
		children = out_neighbors(v,g)
		p = length(parents)
		c = length(children)
		i = length(intersect(parents,children))
		# maximum number of colinks:
		# = p+c-i
		npc = p+c-i
		# correct the result according to the specified density
		if density > 0
			ccs[v] = (ncolinks[v] - density*npc)/(npc*(1-density))
		else
			ccs[v] = ncolinks[v]/npc
		end
	end
	return ccs
end